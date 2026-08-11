// Package core provides an embeddable native IPFS/libp2p node.
package core

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ipfs/boxo/autoconf"
	"github.com/ipfs/boxo/bitswap"
	bsnetiface "github.com/ipfs/boxo/bitswap/network"
	bsnet "github.com/ipfs/boxo/bitswap/network/bsnet"
	"github.com/ipfs/boxo/blockstore"
	"github.com/ipfs/boxo/ipld/merkledag"
	"github.com/ipfs/boxo/ipld/unixfs"
	pb "github.com/ipfs/boxo/ipld/unixfs/pb"
	"github.com/ipfs/boxo/ipns"
	"github.com/ipfs/boxo/namesys"
	"github.com/ipfs/boxo/path"
	"github.com/ipfs/go-block-format"
	"github.com/ipfs/go-cid"
	ipld "github.com/ipfs/go-ipld-format"
	libp2p "github.com/libp2p/go-libp2p"
	dht "github.com/libp2p/go-libp2p-kad-dht"
	dhtpb "github.com/libp2p/go-libp2p-kad-dht/pb"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/pnet"
	"github.com/libp2p/go-libp2p/p2p/host/autorelay"
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
	// ErrRepositoryPathRequired is returned when a native public node has no
	// durable local repository path.
	ErrRepositoryPathRequired = errors.New("native repository path is required")
	// ErrRepositoryLocked is returned when another process owns this repository.
	ErrRepositoryLocked = errors.New("native repository is already locked")
	// ErrNodeAlreadyRunning is returned when a second native core starts in one process.
	ErrNodeAlreadyRunning = errors.New("a native IPFS node is already running in this process")
	// ErrNetworkNotReady is returned until DHT routing and either a relay
	// reservation or a public direct address exist.
	ErrNetworkNotReady = errors.New("public IPFS network is not ready")
)

var runningNativeCore atomic.Bool

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
	Lifecycle        Lifecycle `json:"lifecycle"`
	SafeDiagnostic   string    `json:"safeDiagnostic,omitempty"`
	PeerID           string    `json:"peerId,omitempty"`
	ListenAddrs      []string  `json:"listenAddrs,omitempty"`
	ConnectedPeers   []string  `json:"connectedPeers,omitempty"`
	BootstrapErrors  []string  `json:"bootstrapErrors,omitempty"`
	RelayAddrs       []string  `json:"relayAddrs,omitempty"`
	RelayReady       bool      `json:"relayReady"`
	RoutingTableSize int       `json:"routingTableSize"`
	DhtReady         bool      `json:"dhtReady"`
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

// BitswapStats is an aggregate of the bitswap client and server counters.
type BitswapStats struct {
	BlocksSent       uint64   `json:"blocksSent"`
	BlocksReceived   uint64   `json:"blocksReceived"`
	DataSent         uint64   `json:"dataSent"`
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
	RepositoryPath string
}

// PrivateConfig starts a node intended for a private IPFS network.
type PrivateConfig struct {
	RepositoryPath string
	SwarmKey       []byte
	BootstrapPeers []string
	RelayPeers     []string
	AllowedPeerIDs []string
}

type networkMode uint8

const (
	networkPublic networkMode = iota
	networkPrivate
)

type networkConfig struct {
	mode           networkMode
	repositoryPath string
	swarmKey       []byte
	bootstrapPeers []string
	relayPeers     []string
	allowedPeerIDs []string
}

// Core owns one native node lifecycle state machine.
type Core struct {
	mu              sync.Mutex
	ctx             context.Context
	status          Status
	host            host.Host
	dht             *dht.IpfsDHT
	bitswap         *bitswap.Bitswap
	network         bsnetiface.BitSwapNetwork
	store           blockstore.Blockstore
	repo            *repository
	pins            map[string]PinInfo
	provided        map[string]struct{}
	bootstrap       []string
	key             crypto.PrivKey
	namesys         namesys.NameSystem
	cancel          context.CancelFunc
	networkMode     networkMode
	publicationWake chan struct{}
	publicationWG   sync.WaitGroup
	publicationMu   sync.Mutex
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
		if !runningNativeCore.CompareAndSwap(false, true) {
			return ErrNodeAlreadyRunning
		}
		core.status = Status{Lifecycle: Starting}
		var network networkConfig
		switch value := config.(type) {
		case PublicConfig:
			network = publicNetworkConfig(value)
		case *PublicConfig:
			network = publicNetworkConfig(*value)
		case PrivateConfig:
			network = privateNetworkConfig(value)
		case *PrivateConfig:
			network = privateNetworkConfig(*value)
		}
		if err := core.startNetwork(network); err != nil {
			runningNativeCore.Store(false)
			core.status = Status{Lifecycle: Failed, SafeDiagnostic: err.Error()}
			return err
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
	switch core.status.Lifecycle {
	case Stopped:
		core.mu.Unlock()
		return nil
	case Running, Degraded, Failed:
		core.status = Status{Lifecycle: Stopping}
		cancel, client, kad, h, repo := core.cancel, core.bitswap, core.dht, core.host, core.repo
		core.cancel = nil
		core.bitswap = nil
		core.dht = nil
		core.host = nil
		core.repo = nil
		core.store = nil
		core.network = nil
		core.ctx = nil
		core.pins = make(map[string]PinInfo)
		core.provided = nil
		core.bootstrap = nil
		core.key = nil
		core.namesys = nil
		core.publicationWake = nil
		core.mu.Unlock()

		if cancel != nil {
			cancel()
		}
		core.publicationWG.Wait()
		core.publicationMu.Lock()
		defer core.publicationMu.Unlock()
		if client != nil {
			_ = client.Close()
		}
		if kad != nil {
			_ = kad.Close()
		}
		if h != nil {
			_ = h.Close()
		}
		if repo != nil {
			_ = repo.Close()
		}

		core.mu.Lock()
		runningNativeCore.Store(false)
		core.status = Status{Lifecycle: Stopped}
		core.mu.Unlock()
		return nil
	default:
		core.mu.Unlock()
		return ErrInvalidLifecycleTransition
	}
}

// Status returns a snapshot of the current node state, including live DHT and
// relay readiness so callers can surface when the node is reachable.
func (core *Core) Status() Status {
	core.mu.Lock()
	defer core.mu.Unlock()
	status := core.status
	status.ListenAddrs = append([]string(nil), core.status.ListenAddrs...)
	status.ConnectedPeers = append([]string(nil), core.status.ConnectedPeers...)
	status.BootstrapErrors = append([]string(nil), core.status.BootstrapErrors...)
	if core.host != nil {
		status.ConnectedPeers = status.ConnectedPeers[:0]
		for _, peerID := range core.host.Network().Peers() {
			status.ConnectedPeers = append(status.ConnectedPeers, peerID.String())
		}
		for _, addr := range core.host.Addrs() {
			if isRelayAddr(addr) {
				status.RelayAddrs = append(status.RelayAddrs, addr.String())
			}
		}
	}
	status.RelayReady = len(status.RelayAddrs) > 0
	if core.dht != nil {
		status.RoutingTableSize = core.dht.RoutingTable().Size()
		status.DhtReady = status.RoutingTableSize > 0
	}
	return status
}

func isRelayAddr(addr ma.Multiaddr) bool {
	relay := false
	ma.ForEach(addr, func(c ma.Component) bool {
		if c.Protocol().Code == ma.P_CIRCUIT {
			relay = true
			return false
		}
		return true
	})
	return relay
}

// Capabilities returns the native transports and routing protocol initialized
// by a public node.
func (core *Core) Capabilities() []string {
	core.mu.Lock()
	mode := core.networkMode
	core.mu.Unlock()
	if mode == networkPrivate {
		return []string{"inboundListen", "tcp", "quic", "dhtRouting", "privateSwarmKey", "providerRouting"}
	}
	return []string{"inboundListen", "tcp", "quic", "dhtRouting", "providerRouting", "publicPublication"}
}

func publicNetworkConfig(config PublicConfig) networkConfig {
	return networkConfig{
		mode:           networkPublic,
		repositoryPath: config.RepositoryPath,
		bootstrapPeers: append([]string(nil), config.BootstrapPeers...),
	}
}

func privateNetworkConfig(config PrivateConfig) networkConfig {
	return networkConfig{
		mode:           networkPrivate,
		repositoryPath: config.RepositoryPath,
		swarmKey:       append([]byte(nil), config.SwarmKey...),
		bootstrapPeers: append([]string(nil), config.BootstrapPeers...),
		relayPeers:     append([]string(nil), config.RelayPeers...),
		allowedPeerIDs: append([]string(nil), config.AllowedPeerIDs...),
	}
}

func (core *Core) startNetwork(config networkConfig) error {
	ctx, cancel := context.WithCancel(context.Background())
	repo, err := openRepository(config.repositoryPath)
	if err != nil {
		cancel()
		return err
	}
	key, err := repo.loadOrCreateIdentity()
	if err != nil {
		_ = repo.Close()
		cancel()
		return err
	}
	var h host.Host
	options := []libp2p.Option{libp2p.Identity(key)}
	if config.mode == networkPrivate {
		options = append(options, libp2p.PrivateNetwork(pnet.PSK(config.swarmKey)))
		if len(config.allowedPeerIDs) > 0 {
			allowed, err := configuredAllowedPeers(config)
			if err != nil {
				_ = repo.Close()
				cancel()
				return err
			}
			options = append(options, libp2p.ConnectionGater(newPeerAllowlistGater(allowed)))
		}
		if len(config.relayPeers) > 0 {
			relays, err := parseAddrInfos(config.relayPeers)
			if err != nil {
				_ = repo.Close()
				cancel()
				return err
			}
			options = append(options, libp2p.EnableAutoRelayWithStaticRelays(relays))
		}
	} else {
		options = append(options, libp2p.NATPortMap(), libp2p.EnableHolePunching())
		// Behind NAT the node must obtain a public circuit-relay address so
		// remote peers can dial it; otherwise the DHT provider record only
		// advertises unreachable private addresses. Candidate relays are the
		// peers we are already connected to (public bootstrap peers).
		options = append(options, libp2p.EnableAutoRelayWithPeerSource(func(ctx context.Context, num int) <-chan peer.AddrInfo {
			out := make(chan peer.AddrInfo)
			go func() {
				defer close(out)
				if h == nil {
					return
				}
				for _, pid := range h.Network().Peers() {
					select {
					case <-ctx.Done():
						return
					case out <- peer.AddrInfo{ID: pid, Addrs: h.Peerstore().Addrs(pid)}:
					}
				}
			}()
			return out
		},
			autorelay.WithBootDelay(15*time.Second),
			autorelay.WithMinCandidates(1),
			autorelay.WithMinInterval(10*time.Second),
			autorelay.WithBackoff(time.Minute),
			autorelay.WithNumRelays(1),
		))
	}
	h, err = libp2p.New(options...)
	if err != nil {
		_ = repo.Close()
		cancel()
		core.status = Status{Lifecycle: Failed, SafeDiagnostic: err.Error()}
		return err
	}
	dhtMode := dht.ModeAuto
	if config.mode == networkPrivate {
		dhtMode = dht.ModeServer
	}
	kad, err := dht.New(h, dht.Mode(dhtMode))
	if err != nil {
		_ = h.Close()
		_ = repo.Close()
		cancel()
		return err
	}
	store := repo.store
	network := relayBitswapNetwork{BitSwapNetwork: bsnet.NewFromIpfsHost(h)}
	client := bitswap.New(ctx, network, kad, store)
	ns, err := namesys.NewNameSystem(kad)
	if err != nil {
		_ = client.Close()
		_ = kad.Close()
		_ = h.Close()
		_ = repo.Close()
		cancel()
		return err
	}

	core.host, core.dht, core.bitswap, core.cancel = h, kad, client, cancel
	core.ctx = ctx
	core.network = network
	core.store = store
	core.repo = repo
	core.pins = make(map[string]PinInfo, len(repo.metadata.Pins))
	for rawCID, pin := range repo.metadata.Pins {
		core.pins[rawCID] = pin
	}
	core.provided = make(map[string]struct{})
	for rawCID, metadata := range repo.metadata.Roots {
		if metadata.State == PublicationConfirmed {
			core.provided[rawCID] = struct{}{}
		}
	}
	core.publicationWake = make(chan struct{}, 1)
	core.bootstrap = append([]string(nil), config.bootstrapPeers...)
	core.key = key
	core.namesys = ns
	core.networkMode = config.mode
	core.status.PeerID = h.ID().String()
	for _, addr := range h.Addrs() {
		core.status.ListenAddrs = append(core.status.ListenAddrs, addr.String()+"/p2p/"+h.ID().String())
	}
	for _, raw := range config.bootstrapPeers {
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
	core.publicationWG.Add(1)
	go core.publicationLoop(ctx, core.publicationWake)
	select {
	case core.publicationWake <- struct{}{}:
	default:
	}
	return nil
}

func parseAddrInfos(values []string) ([]peer.AddrInfo, error) {
	result := make([]peer.AddrInfo, 0, len(values))
	for _, raw := range values {
		addr, err := ma.NewMultiaddr(raw)
		if err != nil {
			return nil, err
		}
		info, err := peer.AddrInfoFromP2pAddr(addr)
		if err != nil {
			return nil, err
		}
		result = append(result, *info)
	}
	return result, nil
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
	block, err = client.Client.GetBlock(ctx, parsed)
	if err != nil {
		return nil, err
	}
	if !block.Cid().Equals(parsed) {
		return nil, errors.New("retrieved block CID mismatch")
	}
	return append([]byte(nil), block.RawData()...), nil
}

// NetworkReady reports whether the node can publish a provider record that
// remote peers can route to through a relay or a public direct address.
func (core *Core) NetworkReady() bool {
	status := core.Status()
	core.mu.Lock()
	mode := core.networkMode
	var addrs []ma.Multiaddr
	if core.host != nil {
		addrs = append(addrs, core.host.Addrs()...)
	}
	core.mu.Unlock()
	return networkReadyFor(mode, status, addrs)
}

func networkReadyFor(mode networkMode, status Status, addrs []ma.Multiaddr) bool {
	if mode == networkPrivate {
		return status.DhtReady && len(status.ConnectedPeers) > 0
	}
	return status.DhtReady && (status.RelayReady || hasPublicAddress(addrs))
}

func hasPublicAddress(addrs []ma.Multiaddr) bool {
	for _, addr := range addrs {
		public := false
		ma.ForEach(addr, func(component ma.Component) bool {
			protocol := component.Protocol().Code
			if protocol != ma.P_IP4 && protocol != ma.P_IP6 {
				return true
			}
			ip := net.ParseIP(component.Value())
			if ip != nil && !ip.IsPrivate() && !ip.IsLoopback() && !ip.IsUnspecified() && !ip.IsLinkLocalUnicast() {
				public = true
			}
			return !public
		})
		if public {
			return true
		}
	}
	return false
}

func publicationAddresses(mode networkMode, addrs []ma.Multiaddr) []ma.Multiaddr {
	if mode == networkPrivate {
		return append([]ma.Multiaddr(nil), addrs...)
	}
	result := make([]ma.Multiaddr, 0, len(addrs))
	for _, addr := range addrs {
		if isRelayAddr(addr) || hasPublicAddress([]ma.Multiaddr{addr}) {
			result = append(result, addr)
		}
	}
	return result
}

// Provide announces a locally stored root and persists the successful result.
func (core *Core) Provide(ctx context.Context, rawCID string) error {
	parsed, err := cid.Parse(rawCID)
	if err != nil {
		return err
	}
	core.publicationMu.Lock()
	defer core.publicationMu.Unlock()
	core.mu.Lock()
	kad, repo, store, h, mode := core.dht, core.repo, core.store, core.host, core.networkMode
	core.mu.Unlock()
	if kad == nil || repo == nil || store == nil || h == nil {
		return errors.New("public IPFS node is not running")
	}
	has, err := store.Has(ctx, parsed)
	if err != nil {
		return err
	}
	if !has {
		return fmt.Errorf("content root is not stored locally: %s", parsed)
	}
	now := time.Now().UTC()
	if err := repo.schedulePublication(parsed.String(), now); err != nil {
		return err
	}
	if !core.NetworkReady() {
		if err := repo.recordPublicationAttempt(parsed.String(), now, 0, 0); err != nil {
			return err
		}
		recordProvideFailure(repo, parsed.String(), now, 0, 0, 0, ErrNetworkNotReady)
		return ErrNetworkNotReady
	}
	addrs := publicationAddresses(mode, kad.FilteredAddrs())
	if len(addrs) == 0 {
		if err := repo.recordPublicationAttempt(parsed.String(), now, 0, 0); err != nil {
			return err
		}
		recordProvideFailure(repo, parsed.String(), now, 0, 0, 0, ErrNetworkNotReady)
		return ErrNetworkNotReady
	}
	targets, err := kad.GetClosestPeers(ctx, string(parsed.Hash()))
	if err != nil && len(targets) == 0 {
		if recordErr := repo.recordPublicationAttempt(parsed.String(), now, 0, 0); recordErr != nil {
			return recordErr
		}
		recordProvideFailure(repo, parsed.String(), now, 0, 0, 0, err)
		return err
	}
	required := requiredProviderConfirmations(len(targets))
	if err := repo.recordPublicationAttempt(parsed.String(), now, len(targets), required); err != nil {
		return err
	}
	if err := kad.Provide(ctx, parsed, false); err != nil {
		recordProvideFailure(repo, parsed.String(), time.Now().UTC(), 0, 0, required, err)
		return err
	}
	messenger, err := dhtpb.NewProtocolMessenger(kad.MessageSender())
	if err != nil {
		recordProvideFailure(repo, parsed.String(), time.Now().UTC(), 0, 0, required, err)
		return err
	}
	result, publishErr := publishProviderRecord(ctx, messenger, peer.AddrInfo{ID: h.ID(), Addrs: addrs}, parsed.Hash(), targets, mode == networkPublic)
	if publishErr != nil {
		recordProvideFailure(repo, parsed.String(), time.Now().UTC(), result.WriteSuccesses, result.ConfirmedPeers, result.RequiredConfirmations, publishErr)
		return publishErr
	}
	confirmedAt := time.Now().UTC()
	if err := repo.recordPublicationConfirmed(parsed.String(), confirmedAt, result.WriteSuccesses, result.ConfirmedPeers); err != nil {
		return err
	}
	core.mu.Lock()
	core.provided[parsed.String()] = struct{}{}
	core.mu.Unlock()
	return nil
}

// StartProviding durably schedules a local root for eventual publication.
func (core *Core) StartProviding(ctx context.Context, rawCID string) error {
	parsed, err := cid.Parse(rawCID)
	if err != nil {
		return err
	}
	core.mu.Lock()
	store, repo := core.store, core.repo
	core.mu.Unlock()
	if store == nil || repo == nil {
		return errors.New("public IPFS node is not running")
	}
	has, err := store.Has(ctx, parsed)
	if err != nil {
		return err
	}
	if !has {
		return fmt.Errorf("content root is not stored locally: %s", parsed)
	}
	if err := repo.schedulePublication(parsed.String(), time.Now().UTC()); err != nil {
		return err
	}
	core.wakePublicationWorker()
	return nil
}

// PublicationStatus returns durable publication state for one local root.
func (core *Core) PublicationStatus(rawCID string) (PublicationStatus, error) {
	parsed, err := cid.Parse(rawCID)
	if err != nil {
		return PublicationStatus{}, err
	}
	core.mu.Lock()
	repo := core.repo
	core.mu.Unlock()
	if repo == nil {
		return PublicationStatus{}, errors.New("public IPFS node is not running")
	}
	status, ok := repo.publicationStatus(parsed.String())
	if !ok {
		return PublicationStatus{}, fmt.Errorf("content root is not stored locally: %s", parsed)
	}
	return status, nil
}

// ListPublicationStatuses returns roots enrolled in public publication.
func (core *Core) ListPublicationStatuses() ([]PublicationStatus, error) {
	core.mu.Lock()
	repo := core.repo
	core.mu.Unlock()
	if repo == nil {
		return nil, errors.New("public IPFS node is not running")
	}
	return repo.publicationQueue(), nil
}

// AddAndProvide stores content durably, then waits for its public announcement.
func (core *Core) AddAndProvide(ctx context.Context, data []byte) (string, error) {
	rawCID, err := core.AddBytes(ctx, data)
	if err != nil {
		return "", err
	}
	if err := core.Provide(ctx, rawCID); err != nil {
		return rawCID, err
	}
	return rawCID, nil
}

// AddBytes stores content and returns its content root CID.
//
// Content that fits in one chunk is stored as a single raw block, so its CID
// matches `ipfs add` with CIDv1/raw-leaves and [GetBlock] returns the content
// bytes unchanged. Larger content is split into raw leaves under a dag-pb
// UnixFS file root.
func (core *Core) AddBytes(ctx context.Context, data []byte) (string, error) {
	core.mu.Lock()
	store, client := core.store, core.bitswap
	core.mu.Unlock()
	if store == nil || client == nil {
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
		if err := core.repo.recordRoot(block.Cid().String()); err != nil {
			return "", err
		}
		if err := client.NotifyNewBlocks(ctx, block); err != nil {
			return "", err
		}
		return block.Cid().String(), nil
	}

	var chunkCids []cid.Cid
	var chunkSizes []uint64
	storedBlocks := make([]blocks.Block, 0, len(data)/defaultChunkSize+2)
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
		storedBlocks = append(storedBlocks, leaf)
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
	if err := core.repo.recordRoot(root.Cid().String()); err != nil {
		return "", err
	}
	storedBlocks = append(storedBlocks, rootBlock)
	if err := client.NotifyNewBlocks(ctx, storedBlocks...); err != nil {
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
		block, err := client.Client.GetBlock(ctx, parsed)
		if err != nil {
			return err
		}
		if err := store.Put(ctx, block); err != nil {
			return err
		}
		if err := client.NotifyNewBlocks(ctx, block); err != nil {
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
	if err := core.repo.setPins(core.pins); err != nil {
		return err
	}
	return nil
}

// reprovideInterval is how often the node re-announces its local content roots.
// Provider records expire after ~48h, so re-provision keeps long-running nodes
// discoverable, matching Kubo's periodic reprovide behaviour.
const reprovideInterval = 6 * time.Hour

func publicationRetryDelay(attempt int) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	delay := 30 * time.Second
	for current := 1; current < attempt && delay < 30*time.Minute; current++ {
		delay *= 2
	}
	if delay > 30*time.Minute {
		return 30 * time.Minute
	}
	return delay
}

func publicationIsDue(status PublicationStatus, now time.Time) bool {
	switch status.State {
	case PublicationPending:
		return status.NextRetry == nil || !status.NextRetry.After(now)
	case PublicationFailed, PublicationDegraded:
		return status.NextRetry != nil && !status.NextRetry.After(now)
	case PublicationConfirmed:
		return status.LastPublished == nil || !status.LastPublished.Add(reprovideInterval).After(now)
	default:
		return false
	}
}

func recordProvideFailure(repo *repository, rawCID string, now time.Time, writes, confirmed, required int, cause error) {
	status, _ := repo.publicationStatus(rawCID)
	nextRetry := now.Add(publicationRetryDelay(status.AttemptCount))
	_ = repo.recordPublicationFailure(rawCID, now, writes, confirmed, required, nextRetry, cause.Error())
}

func (core *Core) wakePublicationWorker() {
	core.mu.Lock()
	wake := core.publicationWake
	core.mu.Unlock()
	if wake == nil {
		return
	}
	select {
	case wake <- struct{}{}:
	default:
	}
}

// publicationLoop is the only background provider publisher in the process.
// It serializes retries and periodic reprovides so roots cannot create an
// unbounded number of concurrent DHT operations.
func (core *Core) publicationLoop(ctx context.Context, wake <-chan struct{}) {
	defer core.publicationWG.Done()
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	lastReady := false
	lastAddresses := ""
	for {
		select {
		case <-ctx.Done():
			return
		case <-wake:
		case <-ticker.C:
		}

		core.mu.Lock()
		repo := core.repo
		core.mu.Unlock()
		if repo == nil {
			continue
		}
		now := time.Now().UTC()
		ready, addresses := core.publicationReachabilitySnapshot()
		force := ready && (!lastReady || addresses != lastAddresses)
		lastReady, lastAddresses = ready, addresses
		for _, status := range repo.publicationQueue() {
			due := publicationIsDue(status, now)
			if force && status.State != PublicationConfirmed {
				due = true
			}
			if !due {
				continue
			}
			attemptCtx, cancel := context.WithTimeout(ctx, 60*time.Second)
			_ = core.Provide(attemptCtx, status.CID)
			cancel()
			if ctx.Err() != nil {
				return
			}
		}
	}
}

func (core *Core) publicationReachabilitySnapshot() (bool, string) {
	ready := core.NetworkReady()
	core.mu.Lock()
	kad, mode := core.dht, core.networkMode
	core.mu.Unlock()
	if kad == nil {
		return ready, ""
	}
	addrs := publicationAddresses(mode, kad.FilteredAddrs())
	values := make([]string, 0, len(addrs))
	for _, addr := range addrs {
		values = append(values, addr.String())
	}
	sort.Strings(values)
	return ready, strings.Join(values, "\n")
}

// provide keeps the existing internal call site asynchronous while enrolling
// the root in the durable publication queue.
func (core *Core) provide(ctx context.Context, rawCID string) {
	_ = core.StartProviding(ctx, rawCID)
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
	return core.repo.setPins(core.pins)
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
		BlocksSent:       clientStat.BlocksSent,
		BlocksReceived:   clientStat.BlocksReceived,
		DataSent:         clientStat.DataSent,
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
	// Make the referenced content discoverable, matching `ipfs name publish`
	// which pins and provides the target CID.
	core.provide(ctx, contentCID)
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
		if value.RepositoryPath == "" {
			return ErrRepositoryPathRequired
		}
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
		if value.RepositoryPath == "" {
			return ErrRepositoryPathRequired
		}
		for _, raw := range value.BootstrapPeers {
			if _, err := ma.NewMultiaddr(raw); err != nil {
				return err
			}
		}
		return nil
	case PrivateConfig:
		if value.RepositoryPath == "" {
			return ErrRepositoryPathRequired
		}
		if len(value.SwarmKey) != 32 {
			return ErrInvalidPrivateSwarmKey
		}
		return validatePeerMultiaddrs(value.BootstrapPeers, value.RelayPeers)
	case *PrivateConfig:
		if value == nil {
			return ErrUnsupportedConfig
		}
		if value.RepositoryPath == "" {
			return ErrRepositoryPathRequired
		}
		if len(value.SwarmKey) != 32 {
			return ErrInvalidPrivateSwarmKey
		}
		return validatePeerMultiaddrs(value.BootstrapPeers, value.RelayPeers)
	default:
		return ErrUnsupportedConfig
	}
}

func validatePeerMultiaddrs(groups ...[]string) error {
	for _, values := range groups {
		for _, raw := range values {
			if _, err := ma.NewMultiaddr(raw); err != nil {
				return err
			}
		}
	}
	return nil
}
