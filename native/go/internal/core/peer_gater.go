package core

import (
	"github.com/libp2p/go-libp2p/core/control"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

// peerAllowlistGater applies an optional authenticated-peer allowlist. The PSK
// remains the primary private-network boundary; an empty set intentionally
// permits every peer that completed the PSK handshake.
type peerAllowlistGater struct {
	allowed map[peer.ID]struct{}
}

func newPeerAllowlistGater(peers []peer.ID) *peerAllowlistGater {
	allowed := make(map[peer.ID]struct{}, len(peers))
	for _, peerID := range peers {
		allowed[peerID] = struct{}{}
	}
	return &peerAllowlistGater{allowed: allowed}
}

func configuredAllowedPeers(config networkConfig) ([]peer.ID, error) {
	allowed := make(map[peer.ID]struct{})
	for _, raw := range config.allowedPeerIDs {
		peerID, err := peer.Decode(raw)
		if err != nil {
			return nil, err
		}
		allowed[peerID] = struct{}{}
	}
	for _, group := range [][]string{config.bootstrapPeers, config.relayPeers} {
		for _, raw := range group {
			addr, err := ma.NewMultiaddr(raw)
			if err != nil {
				return nil, err
			}
			info, err := peer.AddrInfoFromP2pAddr(addr)
			if err != nil {
				return nil, err
			}
			allowed[info.ID] = struct{}{}
		}
	}
	result := make([]peer.ID, 0, len(allowed))
	for peerID := range allowed {
		result = append(result, peerID)
	}
	return result, nil
}

func (gater *peerAllowlistGater) permits(peerID peer.ID) bool {
	if len(gater.allowed) == 0 {
		return true
	}
	_, ok := gater.allowed[peerID]
	return ok
}

func (gater *peerAllowlistGater) InterceptPeerDial(peerID peer.ID) bool {
	return gater.permits(peerID)
}

func (gater *peerAllowlistGater) InterceptAddrDial(peerID peer.ID, _ ma.Multiaddr) bool {
	return gater.permits(peerID)
}

func (gater *peerAllowlistGater) InterceptAccept(network.ConnMultiaddrs) bool {
	return true
}

func (gater *peerAllowlistGater) InterceptSecured(_ network.Direction, peerID peer.ID, _ network.ConnMultiaddrs) bool {
	return gater.permits(peerID)
}

func (gater *peerAllowlistGater) InterceptUpgraded(connection network.Conn) (bool, control.DisconnectReason) {
	return gater.permits(connection.RemotePeer()), 0
}
