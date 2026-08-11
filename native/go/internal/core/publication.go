package core

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
	mh "github.com/multiformats/go-multihash"
)

// PublicationState describes the durable public DHT announcement state of a root.
type PublicationState string

const (
	PublicationLocal     PublicationState = "local"
	PublicationPending   PublicationState = "pending"
	PublicationConfirmed PublicationState = "confirmed"
	PublicationDegraded  PublicationState = "degraded"
	PublicationFailed    PublicationState = "failed"
)

// PublicationStatus is safe publication metadata exposed to SDK callers.
type PublicationStatus struct {
	CID                   string           `json:"cid"`
	State                 PublicationState `json:"state"`
	AddedAt               time.Time        `json:"addedAt"`
	LastAttempt           *time.Time       `json:"lastAttempt,omitempty"`
	LastPublished         *time.Time       `json:"lastPublished,omitempty"`
	AttemptCount          int              `json:"attemptCount"`
	TargetPeers           int              `json:"targetPeers"`
	WriteSuccesses        int              `json:"writeSuccesses"`
	ConfirmedPeers        int              `json:"confirmedPeers"`
	RequiredConfirmations int              `json:"requiredConfirmations"`
	PublishError          string           `json:"publishError,omitempty"`
	NextRetry             *time.Time       `json:"nextRetry,omitempty"`
}

type publicationAttemptResult struct {
	TargetPeers           int
	WriteSuccesses        int
	ConfirmedPeers        int
	RequiredConfirmations int
}

type providerMessenger interface {
	PutProviderAddrs(context.Context, peer.ID, mh.Multihash, peer.AddrInfo) error
	GetProviders(context.Context, peer.ID, mh.Multihash) ([]*peer.AddrInfo, []*peer.AddrInfo, error)
}

// PublicationError reports safe aggregate counters without leaking content or keys.
type PublicationError struct {
	Result  publicationAttemptResult
	Details []string
}

func (err *PublicationError) Error() string {
	detail := ""
	if len(err.Details) > 0 {
		detail = ": " + strings.Join(err.Details, "; ")
	}
	return fmt.Sprintf("provider confirmation failed: confirmed %d/%d (writes %d/%d)%s",
		err.Result.ConfirmedPeers, err.Result.RequiredConfirmations,
		err.Result.WriteSuccesses, err.Result.TargetPeers, detail)
}

func requiredProviderConfirmations(targets int) int {
	if targets <= 0 {
		return 0
	}
	required := (targets + 4) / 5
	if required < 1 {
		return 1
	}
	return required
}

func publishProviderRecord(ctx context.Context, messenger providerMessenger, self peer.AddrInfo, key mh.Multihash, targets []peer.ID, requirePublicAddress bool) (publicationAttemptResult, error) {
	result := publicationAttemptResult{TargetPeers: len(targets), RequiredConfirmations: requiredProviderConfirmations(len(targets))}
	if len(targets) == 0 {
		return result, &PublicationError{Result: result, Details: []string{"no DHT target peers"}}
	}
	type peerResult struct {
		wrote     bool
		confirmed bool
		err       error
	}
	results := make(chan peerResult, len(targets))
	var wg sync.WaitGroup
	for _, target := range targets {
		wg.Add(1)
		go func(target peer.ID) {
			defer wg.Done()
			defer func() {
				// A panic raised inside the DHT messenger on this goroutine
				// would otherwise abort the entire host process because the
				// c-shared runtime cannot unwind across the C ABI boundary.
				if recovered := recover(); recovered != nil {
					results <- peerResult{err: fmt.Errorf("%s panic: %v", target, recovered)}
				}
			}()
			peerCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
			defer cancel()
			if err := messenger.PutProviderAddrs(peerCtx, target, key, self); err != nil {
				results <- peerResult{err: fmt.Errorf("%s write: %w", target, err)}
				return
			}
			providers, _, err := messenger.GetProviders(peerCtx, target, key)
			if err != nil {
				results <- peerResult{wrote: true, err: fmt.Errorf("%s confirm: %w", target, err)}
				return
			}
			for _, provider := range providers {
				if provider != nil && provider.ID == self.ID &&
					(!requirePublicAddress || hasReachableProviderAddress(provider.Addrs)) {
					results <- peerResult{wrote: true, confirmed: true}
					return
				}
			}
			results <- peerResult{wrote: true, err: fmt.Errorf("%s did not return provider", target)}
		}(target)
	}
	wg.Wait()
	close(results)
	details := make([]string, 0, 3)
	for item := range results {
		if item.wrote {
			result.WriteSuccesses++
		}
		if item.confirmed {
			result.ConfirmedPeers++
		}
		if item.err != nil && len(details) < 3 {
			details = append(details, item.err.Error())
		}
	}
	if result.ConfirmedPeers < result.RequiredConfirmations {
		return result, &PublicationError{Result: result, Details: details}
	}
	return result, nil
}

func hasReachableProviderAddress(addrs []ma.Multiaddr) bool {
	for _, addr := range addrs {
		if isRelayAddr(addr) || hasPublicAddress([]ma.Multiaddr{addr}) {
			return true
		}
	}
	return false
}
