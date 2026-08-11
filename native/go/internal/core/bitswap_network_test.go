package core

import (
	"context"
	"testing"

	bsmsg "github.com/ipfs/boxo/bitswap/message"
	bsnet "github.com/ipfs/boxo/bitswap/network"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

type recordingBitswapNetwork struct {
	bsnet.BitSwapNetwork
	context context.Context
	sender  *recordingBitswapSender
}

func (network *recordingBitswapNetwork) SendMessage(ctx context.Context, _ peer.ID, _ bsmsg.BitSwapMessage) error {
	network.context = ctx
	return nil
}

func (network *recordingBitswapNetwork) Connect(ctx context.Context, _ peer.AddrInfo) error {
	network.context = ctx
	return nil
}

func (network *recordingBitswapNetwork) NewMessageSender(ctx context.Context, _ peer.ID, _ *bsnet.MessageSenderOpts) (bsnet.MessageSender, error) {
	network.context = ctx
	return network.sender, nil
}

type recordingBitswapSender struct {
	bsnet.MessageSender
	context context.Context
}

func (sender *recordingBitswapSender) SendMsg(ctx context.Context, _ bsmsg.BitSwapMessage) error {
	sender.context = ctx
	return nil
}

func TestRelayBitswapNetworkAllowsLimitedConnections(t *testing.T) {
	recorder := &recordingBitswapNetwork{sender: &recordingBitswapSender{}}
	network := relayBitswapNetwork{BitSwapNetwork: recorder}

	if err := network.SendMessage(context.Background(), "peer", nil); err != nil {
		t.Fatal(err)
	}
	assertLimitedBitswapContext(t, recorder.context)

	if err := network.Connect(context.Background(), peer.AddrInfo{ID: "peer"}); err != nil {
		t.Fatal(err)
	}
	assertLimitedBitswapContext(t, recorder.context)

	sender, err := network.NewMessageSender(context.Background(), "peer", &bsnet.MessageSenderOpts{})
	if err != nil {
		t.Fatal(err)
	}
	assertLimitedBitswapContext(t, recorder.context)
	if err := sender.SendMsg(context.Background(), nil); err != nil {
		t.Fatal(err)
	}
	assertLimitedBitswapContext(t, recorder.sender.context)
}

func assertLimitedBitswapContext(t *testing.T, ctx context.Context) {
	t.Helper()
	allowed, reason := network.GetAllowLimitedConn(ctx)
	if !allowed || reason != bitswapLimitedConnectionReason {
		t.Fatalf("limited connection context = (%t, %q)", allowed, reason)
	}
}
