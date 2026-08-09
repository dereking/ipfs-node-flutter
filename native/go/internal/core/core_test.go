package core

import (
	"context"
	"errors"
	"os"
	"reflect"
	"sync"
	"testing"
	"time"

	dht "github.com/libp2p/go-libp2p-kad-dht"
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
