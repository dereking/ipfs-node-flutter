// Package core provides an embeddable native IPFS/libp2p node.
package core

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/ipfs/boxo/autoconf"
	bsclient "github.com/ipfs/boxo/bitswap/client"
	bsnet "github.com/ipfs/boxo/bitswap/network/bsnet"
	bsnetiface "github.com/ipfs/boxo/bitswap/network"
	"github.com/ipfs/boxo/blockstore"
	"github.com/ipfs/boxo/ipld/merkledag"
	"github.com/ipfs/boxo/ipld/unixfs"
	pb "github.com/ipfs/boxo/ipld/unixfs/pb"
	"github.com/ipfs/boxo/ipns"
	"github.com/ipfs/boxo/namesys"
	"github.com/ipfs/boxo/path"
	"github.com/ipfs/go-block-format"
	"github.com/ipfs/go-cid"
	datastore "github.com/ipfs/go-datastore"
	dssync "github.com/ipfs/go-datastore/sync"
	ipld "github.com/ipfs/go-ipld-format"
	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	dht "github.com/libp2p/go-libp2p-kad-dht"
	ma "github.com/multiformats/go-multiaddr"
	mh "github.com/multiformats/go-multihash"
)

// DefaultPublicBootstrapPeers returns a copy of Boxo's current mainnet
// fallback peers. Callers may replace this list with autoconf results.
func DefaultPublicBootstrapPeers() []string {
	return append([]string(nil), autoconf.FallbackBootstrapPeers...)
}

var (
	// ErrInvalidPrivateSwarmKey is returned when a private node has no swarm key.
	ErrInvalidPrivateSwarmKey = errors.New("private swarm key must not be empty")
	// ErrUnsupportedConfig is returned for a configuration type this foundation
	// does not understand.
	ErrUnsupportedConfig = errors.New("unsupported node configuration")
	// ErrInvalidLifecycleTransition is reserved for lifecycle transitions that
	// cannot be performed by the synchronous foundation.
	ErrInvalidLifecycleTransition = errors.New("invalid node lifecycle transition")
)

// Lifecycle names are shared with the Dart public API and C ABI status JSON.
type Lifecycle string

const (
	Stopped  Lifecycle = "stopped"
	Starting Lifecycle = "starting"
	Running  Lifecycle = "running"
	Degraded Lifecycle = "degraded"
	Stopping Lifecycle = "stopping"
	Failed   Lifecycle = "failed"
)

// Status reports the lifecycle and an optional diagnostic safe for callers.
type Status struct {
	Lifecycle       Lifecycle `json:"lifecycle"`
	SafeDiagnostic  string    `json:"safeDiagnostic,omitempty"`
	PeerID          string    `json:"peerId,omitempty"`
	ListenAddrs     []string  `json:"listenAddrs,omitempty"`
	ConnectedPeers  []string  `json:"connectedPeers,omitempty"`
	BootstrapErrors []string  `json:"bootstrapErrors,omitempty"`
}

// PinType classifies how a content root is pinned.
type PinType string

const (
	// PinDirect pins a single content root without its referenced children.
	PinDirect PinType = "direct"
)

// PinInfo describes one pinned content root.
type PinInfo struct {
	Cid      string    `json:"cid"`
	Type     PinType   `json:"type"`
	PinnedAt time.Time `json:"pinnedAt,omitempty"`
}

// defaultChunkSize is the UnixFS file chunk size used by AddBytes.
const defaultChunkSize = 256 * 1024

// PeerInfo describes a libp2p peer known to this node.
type PeerInfo struct {
	ID    string   `json:"id"`
	Addrs []string `json:"addrs"`
}

// BitswapStats is an aggregate of the bitswap client and network counters.
type BitswapStats struct {
	BlocksReceived   uint64   `json:"blocksReceived"`
	DataReceived     uint64   `json:"dataReceived"`
	Wantlist         []string `json:"wantlist"`
	MessagesSent     uint64   `json:"messagesSent"`
	MessagesReceived uint64   `json:"messagesReceived"`
}

// KeyInfo describes a local IPNS key.
type KeyInfo struct {
	Name   string `json:"name"`
	PeerID string `json:"peerId"`
}

// PublicConfig starts a node configured for the public IPFS network.
type PublicConfig struct {
	BootstrapPeers []string
}

// PrivateConfig starts a node intended for a private IPFS network.
type PrivateConfig struct {
	SwarmKey []byte
}

// Core owns one native node lifecycle state machine.
type Core struct {
	mu        sync.Mutex
	status    Status
	host      host.Host
	dht       *dht.IpfsDHT
	bitswap   *bsclient.Client
	network   bsnetiface.BitSwapNetwork
	store     blockstore.Blockstore
	pins      map[string]PinInfo
	bootstrap []string
	key       crypto.PrivKey
	namesys   namesys.NameSystem
	cancel    context.CancelFunc
}

// New creates a stopped node.
func New() *Core {
	return &Core{
		status: Status{Lifecycle: Stopped},
		pins:   make(map[string]PinInfo),
	}
}

// Start validates a configuration and transitions a stopped node to running.
// Repeated starts are idempotent.
func (core *Core) Start(config any) error {
	if err := validateConfig(config); err != nil {
		return err
	}

	core.mu.Lock()
	defer core.mu.Unlock()

	switch core.status.Lifecycle {
	case Stopped:
		core.status = Status{Lifecycle: Starting}
		var public *PublicConfig
		switch value := config.(type) {
		case PublicConfig:
			public = &value
		case *PublicConfig:
			public = value
		}
		if public != nil {
			if err := core.startPublic(*public); err != nil {
				core.status = Status{Lifecycle: Failed, SafeDiagnostic: err.Error()}
				return err
			}
		}
		core.status.Lifecycle = Running
		return nil
	case Running:
		return nil
	default:
		return ErrInvalidLifecycleTransition
	}
}

// Stop transitions a running node to stopped. Repeated stops are idempotent.
func (core *Core) Stop() error {
	core.mu.Lock()
	defer core.mu.Unlock()

	switch core.status.Lifecycle {
	case Stopped:
		return nil
	case Running, Degraded, Failed:
		core.status = Status{Lifecycle: Stopping}
		if core.host != nil {
			if core.bitswap != nil {
				_ = core.bitswap.Close()
				core.bitswap = nil
			}
			if core.dht != nil {
				_ = core.dht.Close()
				core.dht = nil
			}
			if core.cancel != nil {
				core.cancel()
				core.cancel = nil
			}
			_ = core.host.Close()
			core.host = nil
		}
		core.store = nil
		core.network = nil
		core.pins = make(map[string]PinInfo)
		core.bootstrap = nil
		core.key = nil
		core.namesys = nil
		core.status = Status{Lifecycle: Stopped}
		return nil
	default:
		return ErrInvalidLifecycleTransition
	}
}

// Status returns a snapshot of the current node state.
func (core *Core) Status() Status {
	core.mu.Lock()
	defer core.mu.Unlock()
	status := core.status
	status.ListenAddrs = append([]string(nil), core.status.ListenAddrs...)
	status.ConnectedPeers = append([]string(nil), core.status.ConnectedPeers...)
	status.BootstrapErrors = append([]string(nil), core.status.BootstrapErrors...)
	return status
}

// Capabilities returns the native transports and routing protocol initialized
// by a public node.
func (core *Core) Capabilities() []string {
	return []string{"inboundListen", "tcp", "quic", "dhtRouting"}
}

func (core *Core) startPublic(config PublicConfig) error {
	ctx, cancel := context.WithCancel(context.Background())
	key, _, err := crypto.GenerateKeyPair(crypto.Ed25519, -1)
	if err != nil {
		cancel()
		return err
	}
	h, err := libp2p.New(libp2p.Identity(key))
	if err != nil {
		cancel()
		core.status = Status{Lifecycle: Failed, SafeDiagnostic: err.Error()}
		return err
	}
	kad, err := dht.New(h, dht.Mode(dht.ModeAuto))
	if err != nil {
		_ = h.Close()
		cancel()
		return err
	}
	store := blockstore.NewBlockstore(dssync.MutexWrap(datastore.NewMapDatastore()))
	network := bsnet.NewFromIpfsHost(h)
	client := bsclient.New(ctx, network, kad, store)
	network.Start(client)
	ns, err := namesys.NewNameSystem(kad)
	if err != nil {
		_ = client.Close()
		_ = kad.Close()
		_ = h.Close()
		cancel()
		return err
	}

	core.host, core.dht, core.bitswap, core.cancel = h, kad, client, cancel
	core.network = network
	core.store = store
	core.pins = make(map[string]PinInfo)
	core.bootstrap = append([]string(nil), config.BootstrapPeers...)
	core.key = key
	core.namesys = ns
	core.status.PeerID = h.ID().String()
	for _, addr := range h.Addrs() {
		core.status.ListenAddrs = append(core.status.ListenAddrs, addr.String()+"/p2p/"+h.ID().String())
	}
	for _, raw := range config.BootstrapPeers {
		addr, _ := ma.NewMultiaddr(raw)
		info, err := peer.AddrInfoFromP2pAddr(addr)
		if err != nil {
			core.status.BootstrapErrors = append(core.status.BootstrapErrors, err.Error())
			continue
		}
		dialCtx, dialCancel := context.WithTimeout(ctx, 10*time.Second)
		err = h.Connect(dialCtx, *info)
		dialCancel()
		if err != nil {
			core.status.BootstrapErrors = append(core.status.BootstrapErrors, fmt.Sprintf("%s: %v", info.ID, err))
			continue
		}
		core.status.ConnectedPeers = append(core.status.ConnectedPeers, info.ID.String())
	}
	if err := kad.Bootstrap(ctx); err != nil {
		_ = client.Close()
		_ = kad.Close()
		_ = h.Close()
		cancel()
		core.host, core.dht, core.bitswap, core.cancel = nil, nil, nil, nil
		return err
	}
	return nil
}

// GetBlock retrieves one raw IPFS block by CID from the local store, falling
// back to Bitswap over the network.
func (core *Core) GetBlock(ctx context.Context, rawCID string) ([]byte, error) {
	parsed, err := cid.Parse(rawCID)
	if err != nil {
		return nil, err
	}
	core.mu.Lock()
	store := core.store
	client := core.bitswap
	core.mu.Unlock()
	if store == nil || client == nil {
		return nil, errors.New("public IPFS node is not running")
	}
	block, err := store.Get(ctx, parsed)
	if err == nil {
		return append([]byte(nil), block.RawData()...), nil
	}
	if !ipld.IsNotFound(err) {
		return nil, err
	}
	block, err = client.GetBlock(ctx, parsed)
	if err != nil {
		return nil, err
	}
	if !block.Cid().Equals(parsed) {
		return nil, errors.New("retrieved block CID mismatch")
	}
	return append([]byte(nil), block.RawData()...), nil
}

// AddBytes stores content and returns its content root CID.
//
// Content that fits in one chunk is stored as a single raw block, so its CID
// matches `ipfs add` with CIDv1/raw-leaves and [GetBlock] returns the content
// bytes unchanged. Larger content is split into raw leaves under a dag-pb
// UnixFS file root.
func (core *Core) AddBytes(ctx context.Context, data []byte) (string, error) {
	core.mu.Lock()
	store := core.store
	core.mu.Unlock()
	if store == nil {
		return "", errors.New("public IPFS node is not running")
	}

	dagPrefix, err := merkledag.PrefixForCidVersion(1)
	if err != nil {
		return "", err
	}
	rawPrefix := cid.Prefix{
		Version:  1,
		Codec:    cid.Raw,
		MhType:   mh.SHA2_256,
		MhLength: -1,
	}

	if len(data) <= defaultChunkSize {
		block, err := blocks.NewBlockWithPrefix(data, rawPrefix)
		if err != nil {
			return "", err
		}
		if err := store.Put(ctx, block); err != nil {
			return "", err
		}
		return block.Cid().String(), nil
	}

	var chunkCids []cid.Cid
	var chunkSizes []uint64
	for start := 0; start < len(data); start += defaultChunkSize {
		end := start + defaultChunkSize
		if end > len(data) {
			end = len(data)
		}
		leaf, err := blocks.NewBlockWithPrefix(data[start:end], rawPrefix)
		if err != nil {
			return "", err
		}
		if err := store.Put(ctx, leaf); err != nil {
			return "", err
		}
		chunkCids = append(chunkCids, leaf.Cid())
		chunkSizes = append(chunkSizes, uint64(end-start))
	}
	root, err := buildFileNode(dagPrefix, linksFor(chunkCids, chunkSizes))
	if err != nil {
		return "", err
	}
	rootBlock, err := blocks.NewBlockWithCid(root.RawData(), root.Cid())
	if err != nil {
		return "", err
	}
	if err := store.Put(ctx, rootBlock); err != nil {
		return "", err
	}
	return root.Cid().String(), nil
}

// Pin ensures a content root's block is local and records it as pinned.
func (core *Core) Pin(ctx context.Context, rawCID string) error {
	parsed, err := cid.Parse(rawCID)
	if err != nil {
		return err
	}
	core.mu.Lock()
	store := core.store
	client := core.bitswap
	core.mu.Unlock()
	if store == nil || client == nil {
		return errors.New("public IPFS node is not running")
	}
	has, err := store.Has(ctx, parsed)
	if err != nil {
		return err
	}
	if !has {
		block, err := client.GetBlock(ctx, parsed)
		if err != nil {
			return err
		}
		if err := store.Put(ctx, block); err != nil {
			return err
		}
	}
	core.mu.Lock()
	core.pins[parsed.String()] = PinInfo{
		Cid:      parsed.String(),
		Type:     PinDirect,
		PinnedAt: time.Now(),
	}
	core.mu.Unlock()
	return nil
}

// Unpin removes a content root from the local pin set.
func (core *Core) Unpin(rawCID string) error {
	parsed, err := cid.Parse(rawCID)
	if err != nil {
		return err
	}
	core.mu.Lock()
	defer core.mu.Unlock()
	if core.store == nil {
		return errors.New("public IPFS node is not running")
	}
	if _, ok := core.pins[parsed.String()]; !ok {
		return fmt.Errorf("not pinned: %s", parsed)
	}
	delete(core.pins, parsed.String())
	return nil
}

// ListPins returns the locally pinned content roots.
func (core *Core) ListPins() ([]PinInfo, error) {
	core.mu.Lock()
	defer core.mu.Unlock()
	if core.store == nil {
		return nil, errors.New("public IPFS node is not running")
	}
	result := make([]PinInfo, 0, len(core.pins))
	for _, pin := range core.pins {
		result = append(result, pin)
	}
	return result, nil
}

func buildFileNode(prefix cid.Prefix, links []*ipld.Link) (*merkledag.ProtoNode, error) {
	fsNode := unixfs.NewFSNode(pb.Data_File)
	var total uint64
	for _, link := range links {
		fsNode.AddBlockSize(link.Size)
		total += link.Size
	}
	fsNode.UpdateFilesize(int64(total))
	raw, err := fsNode.GetBytes()
	if err != nil {
		return nil, err
	}
	node := merkledag.NodeWithData(raw)
	if err := node.SetCidBuilder(prefix); err != nil {
		return nil, err
	}
	if err := node.SetLinks(links); err != nil {
		return nil, err
	}
	return node, nil
}

func linksFor(cids []cid.Cid, sizes []uint64) []*ipld.Link {
	links := make([]*ipld.Link, len(cids))
	for i := range cids {
		links[i] = &ipld.Link{Name: "", Size: sizes[i], Cid: cids[i]}
	}
	return links
}

// SwarmPeers returns the peers with open connections to this node.
func (core *Core) SwarmPeers() ([]PeerInfo, error) {
	core.mu.Lock()
	h := core.host
	core.mu.Unlock()
	if h == nil {
		return nil, errors.New("public IPFS node is not running")
	}
	ids := h.Network().Peers()
	result := make([]PeerInfo, 0, len(ids))
	for _, pid := range ids {
		addrs := h.Peerstore().Addrs(pid)
		strings := make([]string, 0, len(addrs))
		for _, addr := range addrs {
			strings = append(strings, addr.String())
		}
		result = append(result, PeerInfo{ID: pid.String(), Addrs: strings})
	}
	return result, nil
}

// SwarmConnect dials a peer encoded as a p2p multiaddr.
func (core *Core) SwarmConnect(ctx context.Context, rawMultiaddr string) error {
	core.mu.Lock()
	h := core.host
	core.mu.Unlock()
	if h == nil {
		return errors.New("public IPFS node is not running")
	}
	addr, err := ma.NewMultiaddr(rawMultiaddr)
	if err != nil {
		return err
	}
	info, err := peer.AddrInfoFromP2pAddr(addr)
	if err != nil {
		return err
	}
	return h.Connect(ctx, *info)
}

// SwarmDisconnect closes all connections to a peer.
func (core *Core) SwarmDisconnect(peerID string) error {
	core.mu.Lock()
	h := core.host
	core.mu.Unlock()
	if h == nil {
		return errors.New("public IPFS node is not running")
	}
	pid, err := peer.Decode(peerID)
	if err != nil {
		return err
	}
	return h.Network().ClosePeer(pid)
}

// BootstrapList returns the configured bootstrap multiaddrs.
func (core *Core) BootstrapList() ([]string, error) {
	core.mu.Lock()
	defer core.mu.Unlock()
	if core.host == nil {
		return nil, errors.New("public IPFS node is not running")
	}
	return append([]string(nil), core.bootstrap...), nil
}

// BootstrapAdd validates and records a bootstrap multiaddr.
func (core *Core) BootstrapAdd(rawMultiaddr string) error {
	core.mu.Lock()
	defer core.mu.Unlock()
	if core.host == nil {
		return errors.New("public IPFS node is not running")
	}
	if _, err := ma.NewMultiaddr(rawMultiaddr); err != nil {
		return err
	}
	for _, existing := range core.bootstrap {
		if existing == rawMultiaddr {
			return nil
		}
	}
	core.bootstrap = append(core.bootstrap, rawMultiaddr)
	return nil
}

// BootstrapRemove removes a bootstrap multiaddr.
func (core *Core) BootstrapRemove(rawMultiaddr string) error {
	core.mu.Lock()
	defer core.mu.Unlock()
	if core.host == nil {
		return errors.New("public IPFS node is not running")
	}
	for index, existing := range core.bootstrap {
		if existing == rawMultiaddr {
			core.bootstrap = append(core.bootstrap[:index], core.bootstrap[index+1:]...)
			return nil
		}
	}
	return fmt.Errorf("not a bootstrap peer: %s", rawMultiaddr)
}

// BitswapStats returns the current bitswap client and network counters.
func (core *Core) BitswapStats() (BitswapStats, error) {
	core.mu.Lock()
	client := core.bitswap
	network := core.network
	core.mu.Unlock()
	if client == nil || network == nil {
		return BitswapStats{}, errors.New("public IPFS node is not running")
	}
	clientStat, err := client.Stat()
	if err != nil {
		return BitswapStats{}, err
	}
	networkStat := network.Stats()
	wantlist := make([]string, 0, len(clientStat.Wantlist))
	for _, c := range clientStat.Wantlist {
		wantlist = append(wantlist, c.String())
	}
	return BitswapStats{
		BlocksReceived:   clientStat.BlocksReceived,
		DataReceived:     clientStat.DataReceived,
		Wantlist:         wantlist,
		MessagesSent:     networkStat.MessagesSent,
		MessagesReceived: networkStat.MessagesRecvd,
	}, nil
}

// FindProviders searches the DHT for peers advertising a content root.
func (core *Core) FindProviders(ctx context.Context, rawCID string) ([]PeerInfo, error) {
	parsed, err := cid.Parse(rawCID)
	if err != nil {
		return nil, err
	}
	core.mu.Lock()
	kad := core.dht
	core.mu.Unlock()
	if kad == nil {
		return nil, errors.New("public IPFS node is not running")
	}
	providers, err := kad.FindProviders(ctx, parsed)
	if err != nil {
		return nil, err
	}
	return addrInfosToPeers(providers), nil
}

// FindPeer locates a peer on the DHT and returns its addresses.
func (core *Core) FindPeer(ctx context.Context, peerID string) (PeerInfo, error) {
	pid, err := peer.Decode(peerID)
	if err != nil {
		return PeerInfo{}, err
	}
	core.mu.Lock()
	h := core.host
	kad := core.dht
	core.mu.Unlock()
	if h == nil || kad == nil {
		return PeerInfo{}, errors.New("public IPFS node is not running")
	}
	if pid == h.ID() {
		addrs := h.Addrs()
		strs := make([]string, 0, len(addrs))
		for _, addr := range addrs {
			strs = append(strs, addr.String())
		}
		return PeerInfo{ID: pid.String(), Addrs: strs}, nil
	}
	info, err := kad.FindPeer(ctx, pid)
	if err != nil {
		return PeerInfo{}, err
	}
	return addrInfoToPeer(info), nil
}

// PublishName publishes a content root under this node's IPNS name.
func (core *Core) PublishName(ctx context.Context, contentCID string) (string, error) {
	core.mu.Lock()
	ns := core.namesys
	key := core.key
	core.mu.Unlock()
	if ns == nil || key == nil {
		return "", errors.New("public IPFS node is not running")
	}
	pid, err := peer.IDFromPrivateKey(key)
	if err != nil {
		return "", err
	}
	value, err := path.NewPath("/ipfs/" + contentCID)
	if err != nil {
		return "", err
	}
	if err := ns.Publish(ctx, key, value); err != nil {
		return "", err
	}
	return ipns.NameFromPeer(pid).String(), nil
}

// ResolveName resolves an IPNS name to a content path.
func (core *Core) ResolveName(ctx context.Context, rawName string) (string, error) {
	core.mu.Lock()
	ns := core.namesys
	core.mu.Unlock()
	if ns == nil {
		return "", errors.New("public IPFS node is not running")
	}
	p, err := path.NewPath(rawName)
	if err != nil {
		return "", err
	}
	result, err := ns.Resolve(ctx, p)
	if err != nil {
		return "", err
	}
	return result.Path.String(), nil
}

// ListKeys returns the local IPNS keys (currently the node's self key).
func (core *Core) ListKeys() ([]KeyInfo, error) {
	core.mu.Lock()
	key := core.key
	core.mu.Unlock()
	if key == nil {
		return nil, errors.New("public IPFS node is not running")
	}
	pid, err := peer.IDFromPrivateKey(key)
	if err != nil {
		return nil, err
	}
	return []KeyInfo{{Name: "self", PeerID: pid.String()}}, nil
}

func addrInfosToPeers(infos []peer.AddrInfo) []PeerInfo {
	result := make([]PeerInfo, 0, len(infos))
	for _, info := range infos {
		result = append(result, addrInfoToPeer(info))
	}
	return result
}

func addrInfoToPeer(info peer.AddrInfo) PeerInfo {
	addrs := make([]string, 0, len(info.Addrs))
	for _, addr := range info.Addrs {
		addrs = append(addrs, addr.String())
	}
	return PeerInfo{ID: info.ID.String(), Addrs: addrs}
}

func validateConfig(config any) error {
	switch value := config.(type) {
	case PublicConfig:
		for _, raw := range value.BootstrapPeers {
			if _, err := ma.NewMultiaddr(raw); err != nil {
				return err
			}
		}
		return nil
	case *PublicConfig:
		if value == nil {
			return ErrUnsupportedConfig
		}
		for _, raw := range value.BootstrapPeers {
			if _, err := ma.NewMultiaddr(raw); err != nil {
				return err
			}
		}
		return nil
	case PrivateConfig:
		if len(value.SwarmKey) == 0 {
			return ErrInvalidPrivateSwarmKey
		}
		return nil
	case *PrivateConfig:
		if value == nil || len(value.SwarmKey) == 0 {
			return ErrInvalidPrivateSwarmKey
		}
		return nil
	default:
		return ErrUnsupportedConfig
	}
}
