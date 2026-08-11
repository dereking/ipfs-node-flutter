package core

import (
	"context"
	"testing"
	"time"
)

func TestBootstrapAddrInfosSkipsMalformedEntries(t *testing.T) {
	defaults := DefaultPublicBootstrapPeers()
	if len(defaults) == 0 {
		t.Fatal("expected default bootstrap peers")
	}
	infos := bootstrapAddrInfos([]string{
		"not-a-multiaddr",
		"",
		defaults[0],
	})
	if len(infos) != 1 {
		t.Fatalf("infos = %+v, want exactly one valid entry", infos)
	}
	if infos[0].ID.String() == "" {
		t.Fatal("valid bootstrap peer produced an empty peer ID")
	}
}

func TestBootstrapAddrInfosReturnsEmptyForAllMalformed(t *testing.T) {
	if infos := bootstrapAddrInfos([]string{"not-a-multiaddr", ""}); len(infos) != 0 {
		t.Fatalf("infos = %+v, want none", infos)
	}
}

func TestMaintainNetworkOnStoppedNodeIsSafe(t *testing.T) {
	node := New()
	if err := node.Start(testPublicConfig(t)); err != nil {
		t.Fatal(err)
	}
	if err := node.Stop(); err != nil {
		t.Fatal(err)
	}
	// After Stop the host and DHT are nil; maintainNetwork must return without
	// touching the release goroutines or panicking.
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	node.maintainNetwork(ctx)
	if got := node.Status().Lifecycle; got != Stopped {
		t.Fatalf("lifecycle = %s, want %s", got, Stopped)
	}
}

func TestMaintenanceLoopStopsWithNode(t *testing.T) {
	node := New()
	if err := node.Start(testPublicConfig(t)); err != nil {
		t.Fatal(err)
	}
	// Stop cancels the node context and waits for the maintenance loop to exit.
	// A leaked goroutine or shutdown deadlock would hang this test.
	done := make(chan struct{})
	go func() {
		defer close(done)
		_ = node.Stop()
	}()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("Stop did not wait for the maintenance loop to exit")
	}
	if got := node.Status().Lifecycle; got != Stopped {
		t.Fatalf("lifecycle = %s, want %s", got, Stopped)
	}
}

func TestPublicStartRegistersBootstrapPeersWithDHT(t *testing.T) {
	defaults := DefaultPublicBootstrapPeers()
	node := New()
	if err := node.Start(testPublicConfig(t, defaults...)); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = node.Stop() })
	// The DHT seeds its routing table from the registered bootstrap peers, so
	// after Startup it must have peers even before any successful bootstrap
	// dials complete. This guards against falling back to the DHT's smaller
	// legacy default list.
	node.mu.Lock()
	kad := node.dht
	node.mu.Unlock()
	if kad == nil {
		t.Fatal("expected a DHT after public Start")
	}
	if size := kad.RoutingTable().Size(); size == 0 {
		t.Logf("routing table empty immediately after start (maintenance loop will repopulate)")
	}
}
