package core

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

const (
	// maintenanceInterval is how often the node rechecks bootstrap connectivity
	// and DHT routing-table health.
	maintenanceInterval = 30 * time.Second
	// bootstrapDialTimeout bounds a single bootstrap peer dial.
	bootstrapDialTimeout = 10 * time.Second
	// dhtBootstrapTimeout bounds a routing-table bootstrap refresh.
	dhtBootstrapTimeout = 20 * time.Second
)

// maintenanceLoop keeps a running node reachable after startup. Transient
// network failures can drop bootstrap connections or leave the DHT routing
// table empty; this loop re-dials and re-bootstraps in the background so a
// brief outage during Start never leaves the node permanently disconnected.
func (core *Core) maintenanceLoop(ctx context.Context) {
	defer core.maintenanceWG.Done()
	defer func() {
		// A panic on this goroutine must never abort the host process because
		// c-shared runtimes cannot unwind across the C ABI boundary.
		if recovered := recover(); recovered != nil {
			core.recordMaintenanceDiagnostic(fmt.Sprintf("maintenance panic: %v", recovered))
		}
	}()
	ticker := time.NewTicker(maintenanceInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		core.maintainNetwork(ctx)
	}
}

// maintainNetwork re-dials disconnected bootstrap peers and refreshes an empty
// DHT routing table. Diagnostics are exposed through Status.BootstrapErrors so
// callers can tell a healthy node from a degraded one.
func (core *Core) maintainNetwork(parent context.Context) {
	core.mu.Lock()
	h, kad, bootstrap := core.host, core.dht, core.bootstrap
	core.mu.Unlock()
	if h == nil || kad == nil {
		return
	}

	connected := make(map[peer.ID]struct{})
	for _, id := range h.Network().Peers() {
		connected[id] = struct{}{}
	}

	var disconnected []string
	for _, raw := range bootstrap {
		addr, err := ma.NewMultiaddr(raw)
		if err != nil {
			continue
		}
		info, err := peer.AddrInfoFromP2pAddr(addr)
		if err != nil {
			continue
		}
		if _, ok := connected[info.ID]; ok {
			continue
		}
		disconnected = append(disconnected, raw)
	}

	bootstrapErrors := make([]string, 0)
	if len(disconnected) > 0 {
		dialed := dialBootstrapPeers(parent, h, disconnected)
		bootstrapErrors = append(bootstrapErrors, dialed.errors...)
	}

	// Refresh the routing table while it is still empty. The DHT's own refresh
	// cadence can take up to an hour, which is far too slow to recover from a
	// bad bootstrap during startup on an unstable network.
	if kad.RoutingTable().Size() == 0 {
		bootstrapCtx, cancel := context.WithTimeout(parent, dhtBootstrapTimeout)
		err := kad.Bootstrap(bootstrapCtx)
		cancel()
		if err != nil {
			bootstrapErrors = append(bootstrapErrors, fmt.Sprintf("dht bootstrap: %v", err))
		}
	}

	core.mu.Lock()
	core.status.BootstrapErrors = bootstrapErrors
	core.mu.Unlock()
}

type bootstrapDialResult struct {
	connected []string
	errors    []string
}

// dialBootstrapPeers connects to bootstrap peers in parallel so one slow or
// unreachable peer cannot delay startup or maintenance. Each peer dial is
// bounded by bootstrapDialTimeout.
func dialBootstrapPeers(ctx context.Context, h host.Host, bootstrap []string) bootstrapDialResult {
	var result bootstrapDialResult
	if len(bootstrap) == 0 {
		return result
	}
	type attempt struct {
		peerID string
		err    error
	}
	results := make(chan attempt, len(bootstrap))
	var group sync.WaitGroup
	for _, raw := range bootstrap {
		addr, err := ma.NewMultiaddr(raw)
		if err != nil {
			results <- attempt{err: err}
			continue
		}
		info, err := peer.AddrInfoFromP2pAddr(addr)
		if err != nil {
			results <- attempt{err: err}
			continue
		}
		group.Add(1)
		go func(info peer.AddrInfo) {
			defer group.Done()
			dialCtx, cancel := context.WithTimeout(ctx, bootstrapDialTimeout)
			err := h.Connect(dialCtx, info)
			cancel()
			results <- attempt{peerID: info.ID.String(), err: err}
		}(*info)
	}
	group.Wait()
	close(results)
	for item := range results {
		if item.err != nil {
			if item.peerID != "" {
				result.errors = append(result.errors, fmt.Sprintf("%s: %v", item.peerID, item.err))
			} else {
				result.errors = append(result.errors, item.err.Error())
			}
			continue
		}
		result.connected = append(result.connected, item.peerID)
	}
	return result
}

func (core *Core) recordMaintenanceDiagnostic(message string) {
	core.mu.Lock()
	defer core.mu.Unlock()
	if core.status.SafeDiagnostic != "" {
		core.status.SafeDiagnostic += "; "
	}
	core.status.SafeDiagnostic += message
}
