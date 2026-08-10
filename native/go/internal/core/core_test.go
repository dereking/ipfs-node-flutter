package core

import (
	"context"
	"errors"
	"os"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/ipfs/go-cid"
	dht "github.com/libp2p/go-libp2p-kad-dht"
	"github.com/libp2p/go-libp2p/core/peer"
)

func TestStartStopIsIdempotent(t *testing.T) {
	node := New()
	if got := node.Status().Lifecycle; got != Stopped {
		t.Fatalf("initial = %s, want %s", got, Stopped)
	}

	if err := node.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	if err := node.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	if got := node.Status().Lifecycle; got != Running {
		t.Fatalf("running = %s, want %s", got, Running)
	}

	if err := node.Stop(); err != nil {
		t.Fatal(err)
	}
	if err := node.Stop(); err != nil {
		t.Fatal(err)
	}
	if got := node.Status().Lifecycle; got != Stopped {
		t.Fatalf("stopped = %s, want %s", got, Stopped)
	}
}

func TestPublicNetworkRetrievesDocumentedCID(t *testing.T) {
	if os.Getenv("IPFS_PUBLIC_INTEGRATION") != "1" {
		t.Skip("set IPFS_PUBLIC_INTEGRATION=1 to use the public IPFS network")
	}

	node := New()
	if err := node.Start(PublicConfig{BootstrapPeers: DefaultPublicBootstrapPeers()}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })

	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	data, err := node.GetBlock(ctx, "bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244")
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "Hello IPFS\n" {
		t.Fatalf("retrieved %q", data)
	}
}

func TestAddBytesStoresContentAndPinRoundtrip(t *testing.T) {
	node := New()
	if err := node.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })
	ctx := context.Background()

	content := "hello add\n"
	rawCID, err := node.AddBytes(ctx, []byte(content))
	if err != nil {
		t.Fatal(err)
	}
	if rawCID == "" {
		t.Fatal("expected a content root CID")
	}

	block, err := node.GetBlock(ctx, rawCID)
	if err != nil {
		t.Fatal(err)
	}
	if string(block) != content {
		t.Fatalf("retrieved %q, want %q", block, content)
	}

	if err := node.Pin(ctx, rawCID); err != nil {
		t.Fatal(err)
	}
	pins, err := node.ListPins()
	if err != nil {
		t.Fatal(err)
	}
	if len(pins) != 1 || pins[0].Cid != rawCID || pins[0].Type != PinDirect {
		t.Fatalf("pins = %+v", pins)
	}

	if err := node.Unpin(rawCID); err != nil {
		t.Fatal(err)
	}
	pins, err = node.ListPins()
	if err != nil {
		t.Fatal(err)
	}
	if len(pins) != 0 {
		t.Fatalf("pins after unpin = %+v", pins)
	}
}

func TestAddBytesMatchesDocumentedCID(t *testing.T) {
	node := New()
	if err := node.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })

	rawCID, err := node.AddBytes(context.Background(), []byte("Hello IPFS\n"))
	if err != nil {
		t.Fatal(err)
	}
	const documentedCID = "bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244"
	if rawCID != documentedCID {
		t.Fatalf("raw block CID = %s, want %s", rawCID, documentedCID)
	}
}

func TestAddBytesChunksLargeContent(t *testing.T) {
	node := New()
	if err := node.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })
	ctx := context.Background()

	content := make([]byte, defaultChunkSize+42)
	for i := range content {
		content[i] = byte('a' + i%26)
	}
	rawCID, err := node.AddBytes(ctx, content)
	if err != nil {
		t.Fatal(err)
	}

	block, err := node.GetBlock(ctx, rawCID)
	if err != nil {
		t.Fatal(err)
	}
	if len(block) == 0 {
		t.Fatal("expected a retrievable dag-pb root block")
	}
}

func TestPinRejectsUnknownCID(t *testing.T) {
	node := New()
	if err := node.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })

	err := node.Unpin("not-a-cid")
	if err == nil {
		t.Fatal("expected invalid CID error")
	}
}

func TestOperationsRequireRunningNode(t *testing.T) {
	node := New()

	if _, err := node.AddBytes(context.Background(), []byte("x")); err == nil {
		t.Fatal("expected AddBytes error on stopped node")
	}
	if err := node.Pin(context.Background(), "bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244"); err == nil {
		t.Fatal("expected Pin error on stopped node")
	}
	if _, err := node.ListPins(); err == nil {
		t.Fatal("expected ListPins error on stopped node")
	}
}

func TestSwarmAndBootstrapManagement(t *testing.T) {
	node := New()
	if err := node.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })
	ctx := context.Background()

	peers, err := node.SwarmPeers()
	if err != nil {
		t.Fatal(err)
	}
	if len(peers) != 0 {
		t.Fatalf("swarm peers = %+v, want empty", peers)
	}

	if err := node.SwarmConnect(ctx, "not-a-multiaddr"); err == nil {
		t.Fatal("expected invalid multiaddr error")
	}
	if err := node.SwarmDisconnect("not-a-peer-id"); err == nil {
		t.Fatal("expected invalid peer id error")
	}

	if list, err := node.BootstrapList(); err != nil || len(list) != 0 {
		t.Fatalf("bootstrap list = %v, %v", list, err)
	}
	const bootstrap = "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"
	if err := node.BootstrapAdd("not-a-multiaddr"); err == nil {
		t.Fatal("expected invalid bootstrap error")
	}
	if err := node.BootstrapAdd(bootstrap); err != nil {
		t.Fatal(err)
	}
	list, err := node.BootstrapList()
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0] != bootstrap {
		t.Fatalf("bootstrap list = %v", list)
	}
	if err := node.BootstrapRemove(bootstrap); err != nil {
		t.Fatal(err)
	}
	if err := node.BootstrapRemove(bootstrap); err == nil {
		t.Fatal("expected error removing a missing bootstrap peer")
	}
}

func TestBitswapStatsAndKeysOnStartedNode(t *testing.T) {
	node := New()
	if err := node.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })

	stats, err := node.BitswapStats()
	if err != nil {
		t.Fatal(err)
	}
	if len(stats.Wantlist) != 0 {
		t.Fatalf("wantlist = %v, want empty", stats.Wantlist)
	}

	keys, err := node.ListKeys()
	if err != nil {
		t.Fatal(err)
	}
	if len(keys) != 1 || keys[0].Name != "self" || keys[0].PeerID == "" {
		t.Fatalf("keys = %+v", keys)
	}
}

func TestPublishAndResolveIPNS(t *testing.T) {
	if os.Getenv("IPFS_PUBLIC_INTEGRATION") != "1" {
		t.Skip("set IPFS_PUBLIC_INTEGRATION=1 to publish IPNS over the public network")
	}

	node := New()
	if err := node.Start(PublicConfig{BootstrapPeers: DefaultPublicBootstrapPeers()}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	rawCID, err := node.AddBytes(ctx, []byte("ipns content"))
	if err != nil {
		t.Fatal(err)
	}
	name, err := node.PublishName(ctx, rawCID)
	if err != nil {
		t.Fatal(err)
	}
	if name == "" {
		t.Fatal("expected an IPNS name")
	}

	resolved, err := node.ResolveName(ctx, "/ipns/"+name)
	if err != nil {
		t.Fatal(err)
	}
	if resolved != "/ipfs/"+rawCID {
		t.Fatalf("resolved = %q, want /ipfs/%s", resolved, rawCID)
	}
}

func TestFindPeerOnSelf(t *testing.T) {
	node := New()
	if err := node.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })

	self := node.Status().PeerID
	info, err := node.FindPeer(context.Background(), self)
	if err != nil {
		t.Fatal(err)
	}
	if info.ID != self {
		t.Fatalf("find peer = %+v, want self %s", info, self)
	}
}

func TestPublicConfigRejectsInvalidBootstrapMultiaddr(t *testing.T) {
	node := New()
	err := node.Start(PublicConfig{BootstrapPeers: []string{"not-a-multiaddr"}})
	if err == nil {
		t.Fatal("expected invalid bootstrap error")
	}
}

func TestPublicStartCreatesLibp2pIdentity(t *testing.T) {
	node := New()
	if err := node.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })

	status := node.Status()
	if status.PeerID == "" {
		t.Fatal("expected peer ID")
	}
	if len(status.ListenAddrs) == 0 {
		t.Fatal("expected at least one listen address")
	}
	if got := node.dht.Mode(); got != dht.ModeAuto {
		t.Fatalf("DHT mode = %v, want auto", got)
	}
}

func TestPublicPointerConfigCreatesLibp2pIdentity(t *testing.T) {
	node := New()
	if err := node.Start(&PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })

	if node.Status().PeerID == "" {
		t.Fatal("expected peer ID")
	}
}

func TestStartRejectsEmptyPrivateSwarmKey(t *testing.T) {
	node := New()
	err := node.Start(PrivateConfig{})
	if !errors.Is(err, ErrInvalidPrivateSwarmKey) {
		t.Fatalf("Start() error = %v, want %v", err, ErrInvalidPrivateSwarmKey)
	}
	if got := node.Status().Lifecycle; got != Stopped {
		t.Fatalf("lifecycle = %s, want %s", got, Stopped)
	}
}

func TestStartRejectsUnknownConfiguration(t *testing.T) {
	node := New()
	err := node.Start(struct{}{})
	if !errors.Is(err, ErrUnsupportedConfig) {
		t.Fatalf("Start() error = %v, want %v", err, ErrUnsupportedConfig)
	}
}

func TestStatusAndCapabilitiesAreSafeDuringConcurrentLifecycleCalls(t *testing.T) {
	node := New()
	var group sync.WaitGroup

	for range 32 {
		group.Add(1)
		go func() {
			defer group.Done()
			_ = node.Start(PublicConfig{})
			_ = node.Stop()
			_ = node.Status()
			_ = node.Capabilities()
		}()
	}
	group.Wait()

	if got := node.Capabilities(); !reflect.DeepEqual(got, []string{"inboundListen", "tcp", "quic", "dhtRouting"}) {
		t.Fatalf("capabilities = %v", got)
	}
}

func TestDiagnosePublicReachability(t *testing.T) {
	if os.Getenv("IPFS_PUBLIC_INTEGRATION") != "1" {
		t.Skip("set IPFS_PUBLIC_INTEGRATION=1")
	}
	node := New()
	if err := node.Start(PublicConfig{BootstrapPeers: DefaultPublicBootstrapPeers()}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })
	ctx := context.Background()

	// Give AutoRelay + DHT time to settle.
	time.Sleep(30 * time.Second)

	status := node.Status()
	t.Logf("connected peers: %d", len(status.ConnectedPeers))
	hasRelay := false
	for _, addr := range status.ListenAddrs {
		if strings.Contains(addr, "p2p-circuit") {
			hasRelay = true
		}
	}
	t.Logf("hasRelayAddress: %v", hasRelay)
	t.Logf("listenAddrs: %v", status.ListenAddrs)

	rawCID, err := node.AddBytes(ctx, []byte("diagnose content"))
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("added cid: %s", rawCID)

	time.Sleep(10 * time.Second)

	parsed, err := cid.Parse(rawCID)
	if err != nil {
		t.Fatal(err)
	}
	providers, err := node.dht.FindProviders(ctx, parsed)
	t.Logf("findProviders err=%v count=%d", err, len(providers))
	for _, p := range providers {
		t.Logf("  provider: %s addrs=%v", p.ID, p.Addrs)
	}
}

func TestTwoNodesShareContentDirectly(t *testing.T) {
	nodeA := New()
	if err := nodeA.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = nodeA.Stop() })
	nodeB := New()
	if err := nodeB.Start(PublicConfig{}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = nodeB.Stop() })
	ctx := context.Background()

	// Dial node A from node B over a direct TCP address.
	info, err := peer.AddrInfoFromString(nodeA.Status().ListenAddrs[0])
	if err != nil {
		t.Fatal(err)
	}
	if err := nodeB.host.Connect(ctx, *info); err != nil {
		t.Fatal(err)
	}

	rawCID, err := nodeA.AddBytes(ctx, []byte("direct share"))
	if err != nil {
		t.Fatal(err)
	}
	time.Sleep(2 * time.Second)

	data, err := nodeB.GetBlock(ctx, rawCID)
	if err != nil {
		t.Fatalf("node B could not fetch from node A: %v", err)
	}
	if string(data) != "direct share" {
		t.Fatalf("retrieved %q", data)
	}
}
