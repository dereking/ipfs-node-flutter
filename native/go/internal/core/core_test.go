package core

import (
	"errors"
	"sync"
	"testing"
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

	if got := node.Capabilities(); len(got) != 0 {
		t.Fatalf("capabilities = %v, want empty", got)
	}
}
