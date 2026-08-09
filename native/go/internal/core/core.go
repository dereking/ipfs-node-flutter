// Package core provides the native node lifecycle foundation. It deliberately
// does not construct a libp2p host yet.
package core

import (
	"errors"
	"sync"
)

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
	Lifecycle      Lifecycle `json:"lifecycle"`
	SafeDiagnostic string    `json:"safeDiagnostic,omitempty"`
}

// PublicConfig starts a node configured for the public IPFS network. Network
// connectivity is intentionally not implemented at the foundation stage.
type PublicConfig struct{}

// PrivateConfig starts a node intended for a private IPFS network.
type PrivateConfig struct {
	SwarmKey []byte
}

// Core owns one native node lifecycle state machine.
type Core struct {
	mu     sync.Mutex
	status Status
}

// New creates a stopped node.
func New() *Core {
	return &Core{status: Status{Lifecycle: Stopped}}
}

// Start validates a configuration and transitions a stopped node to running.
// Repeated starts are idempotent. This foundation performs no network work.
func (core *Core) Start(config any) error {
	if err := validateConfig(config); err != nil {
		return err
	}

	core.mu.Lock()
	defer core.mu.Unlock()

	switch core.status.Lifecycle {
	case Stopped:
		core.status = Status{Lifecycle: Starting}
		core.status = Status{Lifecycle: Running}
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
	return core.status
}

// Capabilities returns no protocol or transport capabilities in this stage.
func (core *Core) Capabilities() []string {
	return []string{}
}

func validateConfig(config any) error {
	switch value := config.(type) {
	case PublicConfig, *PublicConfig:
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
