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
	"github.com/ipfs/boxo/blockstore"
	"github.com/ipfs/go-cid"
	datastore "github.com/ipfs/go-datastore"
	dssync "github.com/ipfs/go-datastore/sync"
	libp2p "github.com/libp2p/go-libp2p"
	dht "github.com/libp2p/go-libp2p-kad-dht"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
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
	mu      sync.Mutex
	status  Status
	host    host.Host
	dht     *dht.IpfsDHT
	bitswap *bsclient.Client
	cancel  context.CancelFunc
}

// New creates a stopped node.
func New() *Core {
	return &Core{status: Status{Lifecycle: Stopped}}
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
	h, err := libp2p.New()
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

	core.host, core.dht, core.bitswap, core.cancel = h, kad, client, cancel
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

// GetBlock retrieves and verifies one raw IPFS block by CID through Bitswap.
func (core *Core) GetBlock(ctx context.Context, rawCID string) ([]byte, error) {
	parsed, err := cid.Parse(rawCID)
	if err != nil {
		return nil, err
	}
	core.mu.Lock()
	client := core.bitswap
	core.mu.Unlock()
	if client == nil {
		return nil, errors.New("public IPFS node is not running")
	}
	block, err := client.GetBlock(ctx, parsed)
	if err != nil {
		return nil, err
	}
	if !block.Cid().Equals(parsed) {
		return nil, errors.New("retrieved block CID mismatch")
	}
	return append([]byte(nil), block.RawData()...), nil
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
