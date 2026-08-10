package core

import (
	"bytes"
	"context"
	"errors"
	"os"
	"reflect"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/ipfs/go-cid"
	dht "github.com/libp2p/go-libp2p-kad-dht"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

func testPublicConfig(t *testing.T, bootstrapPeers ...string) PublicConfig {
	t.Helper()
	return PublicConfig{
		RepositoryPath: t.TempDir(),
		BootstrapPeers: bootstrapPeers,
	}
}

func TestPrivateStartCreatesProtectedPersistentNode(t *testing.T) {
	node := New()
	config := PrivateConfig{
		RepositoryPath: t.TempDir(),
		SwarmKey:       bytes.Repeat([]byte{7}, 32),
	}
	if err := node.Start(config); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })
	if node.host == nil || node.store == nil || node.dht == nil {
		t.Fatal("private node did not initialize the shared stack")
	}
	if node.networkMode != networkPrivate {
		t.Fatalf("network mode = %v, want private", node.networkMode)
	}
	capabilities := node.Capabilities()
	for _, capability := range []string{"privateSwarmKey", "providerRouting"} {
		if !slices.Contains(capabilities, capability) {
			t.Fatalf("private capabilities %v do not contain %q", capabilities, capability)
		}
	}
	if slices.Contains(capabilities, "publicPublication") {
		t.Fatalf("private capabilities unexpectedly contain publicPublication: %v", capabilities)
	}
}

func TestPrivateConfigRequiresRepositoryAnd32BytePSK(t *testing.T) {
	if err := New().Start(PrivateConfig{SwarmKey: make([]byte, 32)}); !errors.Is(err, ErrRepositoryPathRequired) {
		t.Fatalf("missing repository error = %v", err)
	}
	if err := New().Start(PrivateConfig{RepositoryPath: t.TempDir(), SwarmKey: []byte{1}}); !errors.Is(err, ErrInvalidPrivateSwarmKey) {
		t.Fatalf("short PSK error = %v", err)
	}
}

func TestNetworkReadinessDependsOnSelectedNetwork(t *testing.T) {
	status := Status{DhtReady: true, ConnectedPeers: []string{"12D3PrivatePeer"}}
	if !networkReadyFor(networkPrivate, status, nil) {
		t.Fatal("private routing should be ready with a DHT peer")
	}
	if networkReadyFor(networkPublic, status, nil) {
		t.Fatal("public routing must still require a relay or public address")
	}
}

func TestPeerAllowlistGaterPermitsOnlyConfiguredPeers(t *testing.T) {
	allowed := peer.ID("allowed-peer")
	blocked := peer.ID("blocked-peer")
	gater := newPeerAllowlistGater([]peer.ID{allowed})
	if !gater.InterceptPeerDial(allowed) {
		t.Fatal("configured peer was blocked")
	}
	if gater.InterceptPeerDial(blocked) {
		t.Fatal("unconfigured peer was allowed")
	}
	if !gater.InterceptSecured(network.DirInbound, allowed, nil) {
		t.Fatal("configured inbound peer was blocked")
	}
	if gater.InterceptSecured(network.DirInbound, blocked, nil) {
		t.Fatal("unconfigured inbound peer was allowed")
	}
}

func TestEmptyPeerAllowlistPermitsPSKAuthenticatedPeers(t *testing.T) {
	gater := newPeerAllowlistGater(nil)
	if !gater.InterceptPeerDial(peer.ID("private-peer")) {
		t.Fatal("empty allowlist should permit PSK-authenticated peers")
	}
}

func TestConfiguredAllowedPeersIncludesExplicitBootstrapAndRelayPeers(t *testing.T) {
	defaults := DefaultPublicBootstrapPeers()
	if len(defaults) < 2 {
		t.Fatal("expected at least two fallback peers")
	}
	bootstrapAddr, err := ma.NewMultiaddr(defaults[0])
	if err != nil {
		t.Fatal(err)
	}
	bootstrap, err := peer.AddrInfoFromP2pAddr(bootstrapAddr)
	if err != nil {
		t.Fatal(err)
	}
	relayAddr, err := ma.NewMultiaddr(defaults[1])
	if err != nil {
		t.Fatal(err)
	}
	relay, err := peer.AddrInfoFromP2pAddr(relayAddr)
	if err != nil {
		t.Fatal(err)
	}

	configured, err := configuredAllowedPeers(networkConfig{
		allowedPeerIDs: []string{bootstrap.ID.String()},
		bootstrapPeers: []string{defaults[0]},
		relayPeers:     []string{defaults[1]},
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []peer.ID{bootstrap.ID, relay.ID} {
		if !slices.Contains(configured, expected) {
			t.Fatalf("configured peers %v do not contain %s", configured, expected)
		}
	}
}

func TestStartStopIsIdempotent(t *testing.T) {
	node := New()
	if got := node.Status().Lifecycle; got != Stopped {
		t.Fatalf("initial = %s, want %s", got, Stopped)
	}

	if err := node.Start(testPublicConfig(t)); err != nil {
		t.Fatal(err)
	}
	if err := node.Start(testPublicConfig(t)); err != nil {
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
	if err := node.Start(testPublicConfig(t, DefaultPublicBootstrapPeers()...)); err != nil {
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
	if err := node.Start(testPublicConfig(t)); err != nil {
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

func TestRepositoryRestoresBlocksAndPins(t *testing.T) {
	path := t.TempDir()
	first := New()
	if err := first.Start(PublicConfig{RepositoryPath: path}); err != nil {
		t.Fatal(err)
	}
	cid, err := first.AddBytes(context.Background(), []byte("durable content"))
	if err != nil {
		t.Fatal(err)
	}
	if err := first.Pin(context.Background(), cid); err != nil {
		t.Fatal(err)
	}
	if err := first.repo.recordPublication(cid, time.Now().UTC(), ""); err != nil {
		t.Fatal(err)
	}
	if err := first.Stop(); err != nil {
		t.Fatal(err)
	}

	second := New()
	if err := second.Start(PublicConfig{RepositoryPath: path}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = second.Stop() })
	got, err := second.GetBlock(context.Background(), cid)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "durable content" {
		t.Fatalf("block = %q", got)
	}
	pins, err := second.ListPins()
	if err != nil {
		t.Fatal(err)
	}
	if len(pins) != 1 || pins[0].Cid != cid {
		t.Fatalf("pins = %+v", pins)
	}
	if _, ok := second.provided[cid]; !ok {
		t.Fatalf("published CID %s was not restored for periodic reprovide", cid)
	}
}

func TestOnlyOneNativeCoreRunsPerProcess(t *testing.T) {
	first := New()
	if err := first.Start(PublicConfig{RepositoryPath: t.TempDir()}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = first.Stop() })
	second := New()
	if err := second.Start(PublicConfig{RepositoryPath: t.TempDir()}); !errors.Is(err, ErrNodeAlreadyRunning) {
		t.Fatalf("Start() error = %v, want ErrNodeAlreadyRunning", err)
	}
}

func TestProvideRequiresNetworkReadiness(t *testing.T) {
	node := New()
	if err := node.Start(testPublicConfig(t)); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })
	cid, err := node.AddBytes(context.Background(), []byte("local only"))
	if err != nil {
		t.Fatal(err)
	}
	if err := node.Provide(context.Background(), cid); !errors.Is(err, ErrNetworkNotReady) {
		t.Fatalf("Provide() error = %v, want ErrNetworkNotReady", err)
	}
}

func TestPublicAddressMakesNetworkReadyWithoutRelay(t *testing.T) {
	public, err := ma.NewMultiaddr("/ip4/8.8.8.8/tcp/4001")
	if err != nil {
		t.Fatal(err)
	}
	private, err := ma.NewMultiaddr("/ip4/192.168.1.10/tcp/4001")
	if err != nil {
		t.Fatal(err)
	}
	if !hasPublicAddress([]ma.Multiaddr{public}) {
		t.Fatal("expected public address to be reachable")
	}
	if hasPublicAddress([]ma.Multiaddr{private}) {
		t.Fatal("private address must not be treated as publicly reachable")
	}
}

func TestAddBytesMatchesDocumentedCID(t *testing.T) {
	node := New()
	if err := node.Start(testPublicConfig(t)); err != nil {
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
	if err := node.Start(testPublicConfig(t)); err != nil {
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
	if err := node.Start(testPublicConfig(t)); err != nil {
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
	if err := node.Start(testPublicConfig(t)); err != nil {
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
	if err := node.Start(testPublicConfig(t)); err != nil {
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
	if err := node.Start(testPublicConfig(t, DefaultPublicBootstrapPeers()...)); err != nil {
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
	if err := node.Start(testPublicConfig(t)); err != nil {
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
	err := node.Start(testPublicConfig(t, "not-a-multiaddr"))
	if err == nil {
		t.Fatal("expected invalid bootstrap error")
	}
}

func TestPublicStartCreatesLibp2pIdentity(t *testing.T) {
	node := New()
	if err := node.Start(testPublicConfig(t)); err != nil {
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
	if err := node.Start(&PublicConfig{RepositoryPath: t.TempDir()}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })

	if node.Status().PeerID == "" {
		t.Fatal("expected peer ID")
	}
}

func TestStartRejectsEmptyPrivateSwarmKey(t *testing.T) {
	node := New()
	err := node.Start(PrivateConfig{RepositoryPath: t.TempDir()})
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
			_ = node.Start(testPublicConfig(t))
			_ = node.Stop()
			_ = node.Status()
			_ = node.Capabilities()
		}()
	}
	group.Wait()

	if got := node.Capabilities(); !reflect.DeepEqual(got, []string{"inboundListen", "tcp", "quic", "dhtRouting", "providerRouting", "publicPublication"}) {
		t.Fatalf("capabilities = %v", got)
	}
}

func TestDiagnosePublicReachability(t *testing.T) {
	if os.Getenv("IPFS_PUBLIC_INTEGRATION") != "1" {
		t.Skip("set IPFS_PUBLIC_INTEGRATION=1")
	}
	node := New()
	if err := node.Start(testPublicConfig(t, DefaultPublicBootstrapPeers()...)); err != nil {
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

func TestSecondNodeDoesNotStartWhileFirstRuns(t *testing.T) {
	nodeA := New()
	if err := nodeA.Start(testPublicConfig(t)); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = nodeA.Stop() })
	nodeB := New()
	if err := nodeB.Start(testPublicConfig(t)); !errors.Is(err, ErrNodeAlreadyRunning) {
		t.Fatalf("Start() error = %v, want ErrNodeAlreadyRunning", err)
	}
}
