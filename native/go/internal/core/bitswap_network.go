package core

import (
	"context"

	bsmsg "github.com/ipfs/boxo/bitswap/message"
	bsnet "github.com/ipfs/boxo/bitswap/network"
	libp2pnetwork "github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

const bitswapLimitedConnectionReason = "ipfs-bitswap"

// relayBitswapNetwork permits Bitswap replies over circuit-relay connections.
// libp2p marks relayed connections as limited, so opening the response stream
// requires an explicit opt-in even though the peer already reached this node.
type relayBitswapNetwork struct {
	bsnet.BitSwapNetwork
}

func (network relayBitswapNetwork) SendMessage(ctx context.Context, target peer.ID, message bsmsg.BitSwapMessage) error {
	return network.BitSwapNetwork.SendMessage(allowBitswapLimitedConnection(ctx), target, message)
}

func (network relayBitswapNetwork) Connect(ctx context.Context, target peer.AddrInfo) error {
	return network.BitSwapNetwork.Connect(allowBitswapLimitedConnection(ctx), target)
}

func (network relayBitswapNetwork) NewMessageSender(ctx context.Context, target peer.ID, options *bsnet.MessageSenderOpts) (bsnet.MessageSender, error) {
	sender, err := network.BitSwapNetwork.NewMessageSender(allowBitswapLimitedConnection(ctx), target, options)
	if err != nil {
		return nil, err
	}
	return relayBitswapMessageSender{MessageSender: sender}, nil
}

type relayBitswapMessageSender struct {
	bsnet.MessageSender
}

func (sender relayBitswapMessageSender) SendMsg(ctx context.Context, message bsmsg.BitSwapMessage) error {
	return sender.MessageSender.SendMsg(allowBitswapLimitedConnection(ctx), message)
}

func allowBitswapLimitedConnection(ctx context.Context) context.Context {
	return libp2pnetwork.WithAllowLimitedConn(ctx, bitswapLimitedConnectionReason)
}
