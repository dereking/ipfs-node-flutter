package core

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/ipfs/go-cid"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
	mh "github.com/multiformats/go-multihash"
)

func TestLegacyPublicationMigrationDoesNotTrustLastPublished(t *testing.T) {
	path := t.TempDir()
	legacy := `{"pins":{},"roots":{"bafklegacy":{"addedAt":"2026-08-10T10:00:00Z","lastPublished":"2026-08-10T11:00:00Z"}}}`
	if err := os.WriteFile(filepath.Join(path, repositoryMetadataFile), []byte(legacy), 0o600); err != nil {
		t.Fatal(err)
	}
	repo, err := openRepository(path)
	if err != nil {
		t.Fatal(err)
	}
	defer repo.Close()

	status, ok := repo.publicationStatus("bafklegacy")
	if !ok {
		t.Fatal("legacy root missing after migration")
	}
	if status.State != PublicationPending {
		t.Fatalf("state = %q, want %q", status.State, PublicationPending)
	}
	if status.LastPublished != nil {
		t.Fatalf("unverified LastPublished = %v, want nil", status.LastPublished)
	}
}

type fakeProviderMessenger struct {
	putErrors map[peer.ID]error
	providers map[peer.ID][]peer.AddrInfo
}

func (f *fakeProviderMessenger) PutProviderAddrs(_ context.Context, target peer.ID, _ mh.Multihash, _ peer.AddrInfo) error {
	return f.putErrors[target]
}

func (f *fakeProviderMessenger) GetProviders(_ context.Context, target peer.ID, _ mh.Multihash) ([]*peer.AddrInfo, []*peer.AddrInfo, error) {
	infos := f.providers[target]
	result := make([]*peer.AddrInfo, 0, len(infos))
	for index := range infos {
		info := infos[index]
		result = append(result, &info)
	}
	return result, nil, nil
}

var _ providerMessenger = (*fakeProviderMessenger)(nil)

func TestRequiredProviderConfirmations(t *testing.T) {
	tests := map[int]int{0: 0, 1: 1, 4: 1, 5: 1, 6: 2, 20: 4}
	for targets, want := range tests {
		if got := requiredProviderConfirmations(targets); got != want {
			t.Fatalf("targets %d: got %d, want %d", targets, got, want)
		}
	}
}

func TestStrictProvideRequiresRemoteConfirmation(t *testing.T) {
	self := peer.AddrInfo{ID: peer.ID("self"), Addrs: []ma.Multiaddr{ma.StringCast("/ip4/203.0.113.10/tcp/4001")}}
	targets := []peer.ID{"one", "two", "three", "four", "five"}
	messenger := &fakeProviderMessenger{providers: map[peer.ID][]peer.AddrInfo{
		"one": {{ID: self.ID}},
	}}
	result, err := publishProviderRecord(context.Background(), messenger, self, mh.Multihash("key"), targets, true)
	if err == nil {
		t.Fatal("publish succeeded without remote confirmation")
	}
	if result.WriteSuccesses != 5 || result.ConfirmedPeers != 0 || result.RequiredConfirmations != 1 {
		t.Fatalf("result = %+v", result)
	}
}

func TestStrictProvideSucceedsAtConfirmationThreshold(t *testing.T) {
	self := peer.AddrInfo{ID: peer.ID("self"), Addrs: []ma.Multiaddr{ma.StringCast("/ip4/203.0.113.10/tcp/4001")}}
	targets := []peer.ID{"one", "two", "three", "four", "five", "six"}
	messenger := &fakeProviderMessenger{providers: map[peer.ID][]peer.AddrInfo{
		"one": {{ID: self.ID, Addrs: self.Addrs}},
		"two": {{ID: self.ID, Addrs: self.Addrs}},
	}}
	result, err := publishProviderRecord(context.Background(), messenger, self, mh.Multihash("key"), targets, true)
	if err != nil {
		t.Fatal(err)
	}
	if result.ConfirmedPeers != 2 || result.RequiredConfirmations != 2 {
		t.Fatalf("result = %+v", result)
	}
}

func TestAddAndProvideReturnsDurableCIDOnPublicationFailure(t *testing.T) {
	node := New()
	if err := node.Start(PublicConfig{RepositoryPath: t.TempDir()}); err != nil {
		t.Fatal(err)
	}
	defer node.Stop()
	rawCID, err := node.AddAndProvide(context.Background(), []byte("durable despite offline publication"))
	if !errors.Is(err, ErrNetworkNotReady) {
		t.Fatalf("error = %v, want ErrNetworkNotReady", err)
	}
	if rawCID == "" {
		t.Fatal("AddAndProvide discarded durable CID")
	}
}

func TestPublicationMetadataTransitions(t *testing.T) {
	repo, err := openRepository(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer repo.Close()
	const rawCID = "bafktest"
	added := time.Date(2026, 8, 10, 10, 0, 0, 0, time.UTC)
	repo.metadata.Roots[rawCID] = contentMetadata{AddedAt: added}

	attempted := added.Add(time.Minute)
	if err := repo.schedulePublication(rawCID, attempted); err != nil {
		t.Fatal(err)
	}
	if err := repo.recordPublicationAttempt(rawCID, attempted, 20, 4); err != nil {
		t.Fatal(err)
	}
	failedAt := attempted.Add(time.Second)
	nextRetry := failedAt.Add(30 * time.Second)
	if err := repo.recordPublicationFailure(rawCID, failedAt, 3, 2, 4, nextRetry, "confirmed 2/4"); err != nil {
		t.Fatal(err)
	}
	failed, _ := repo.publicationStatus(rawCID)
	if failed.State != PublicationFailed || failed.LastPublished != nil || failed.AttemptCount != 1 {
		t.Fatalf("failed status = %+v", failed)
	}
	if failed.WriteSuccesses != 3 || failed.ConfirmedPeers != 2 || failed.RequiredConfirmations != 4 {
		t.Fatalf("failed counters = %+v", failed)
	}

	confirmedAt := failedAt.Add(time.Minute)
	if err := repo.recordPublicationAttempt(rawCID, confirmedAt, 20, 4); err != nil {
		t.Fatal(err)
	}
	if err := repo.recordPublicationConfirmed(rawCID, confirmedAt, 7, 5); err != nil {
		t.Fatal(err)
	}
	confirmed, _ := repo.publicationStatus(rawCID)
	if confirmed.State != PublicationConfirmed || confirmed.LastPublished == nil || !confirmed.LastPublished.Equal(confirmedAt) {
		t.Fatalf("confirmed status = %+v", confirmed)
	}
	if confirmed.PublishError != "" || confirmed.NextRetry != nil || confirmed.AttemptCount != 2 {
		t.Fatalf("confirmed metadata = %+v", confirmed)
	}
}

func TestPublicationRetryDelayUsesBoundedExponentialBackoff(t *testing.T) {
	t.Parallel()

	if got := publicationRetryDelay(1); got != 30*time.Second {
		t.Fatalf("first retry delay = %s, want 30s", got)
	}
	if got := publicationRetryDelay(4); got != 4*time.Minute {
		t.Fatalf("fourth retry delay = %s, want 4m", got)
	}
	if got := publicationRetryDelay(20); got != 30*time.Minute {
		t.Fatalf("bounded retry delay = %s, want 30m", got)
	}
}

func TestPublicationIsDueForPendingRetryAndReprovide(t *testing.T) {
	t.Parallel()

	now := time.Now().UTC()
	past := now.Add(-time.Second)
	recent := now.Add(-time.Hour)
	stale := now.Add(-reprovideInterval - time.Second)

	for name, status := range map[string]PublicationStatus{
		"pending":         {State: PublicationPending},
		"failed retry":    {State: PublicationFailed, NextRetry: &past},
		"stale confirmed": {State: PublicationConfirmed, LastPublished: &stale},
	} {
		if !publicationIsDue(status, now) {
			t.Errorf("%s publication should be due", name)
		}
	}
	if publicationIsDue(PublicationStatus{State: PublicationConfirmed, LastPublished: &recent}, now) {
		t.Fatal("recent confirmed publication should not be due")
	}
}

func TestPublicProviderCanBeFetchedByExternalKubo(t *testing.T) {
	if os.Getenv("IPFS_KUBO_INTEGRATION") != "1" {
		t.Skip("set IPFS_KUBO_INTEGRATION=1 with a running Kubo daemon")
	}
	probeCtx, cancelProbe := context.WithTimeout(context.Background(), 3*time.Second)
	probe, err := kuboAPI(probeCtx, "id", nil)
	cancelProbe()
	if err != nil {
		t.Skipf("Kubo API is not available: %v: %s", err, probe)
	}
	var kuboIdentity struct {
		ID string `json:"ID"`
	}
	if err := json.Unmarshal(probe, &kuboIdentity); err != nil {
		t.Fatal(err)
	}
	kuboPeer, err := peer.Decode(kuboIdentity.ID)
	if err != nil {
		t.Fatal(err)
	}

	node := New()
	if err := node.Start(PublicConfig{
		RepositoryPath: t.TempDir(),
		BootstrapPeers: DefaultPublicBootstrapPeers(),
	}); err != nil {
		t.Fatal(err)
	}
	defer node.Stop()

	content := []byte(fmt.Sprintf("strict provider integration %d\n", time.Now().UnixNano()))
	rawCID, err := node.AddBytes(context.Background(), content)
	if err != nil {
		t.Fatal(err)
	}
	if err := node.StartProviding(context.Background(), rawCID); err != nil {
		t.Fatal(err)
	}
	publishDeadline := time.Now().Add(5 * time.Minute)
	lastAttempt := -1
	for time.Now().Before(publishDeadline) {
		status, statusErr := node.PublicationStatus(rawCID)
		if statusErr != nil {
			t.Fatal(statusErr)
		}
		if status.AttemptCount != lastAttempt {
			nodeStatus := node.Status()
			t.Logf("relay=%t routing=%d peers=%d publication=%+v",
				nodeStatus.RelayReady, nodeStatus.RoutingTableSize,
				len(nodeStatus.ConnectedPeers), status)
			lastAttempt = status.AttemptCount
		}
		if status.State == PublicationConfirmed {
			break
		}
		time.Sleep(2 * time.Second)
	}
	status, _ := node.PublicationStatus(rawCID)
	if status.State != PublicationConfirmed {
		t.Fatalf("publication queue did not confirm: node=%+v publication=%+v", node.Status(), status)
	}
	node.mu.Lock()
	confirmedAddrs := publicationAddresses(node.networkMode, node.dht.FilteredAddrs())
	node.mu.Unlock()
	t.Logf("confirmed provider addresses: %v", confirmedAddrs)
	providerCtx, cancelProviders := context.WithTimeout(context.Background(), 2*time.Minute)
	providerResult, err := kuboAPI(providerCtx, "routing/findprovs", url.Values{
		"arg": {rawCID}, "num-providers": {"1"},
	})
	cancelProviders()
	if err != nil {
		t.Fatalf("Kubo API did not find provider: %v: %s", err, providerResult)
	}
	peerID := node.Status().PeerID
	if !bytes.Contains(providerResult, []byte(peerID)) {
		t.Fatalf("Kubo provider result did not include SDK peer %s", peerID)
	}
	t.Logf("Kubo found SDK provider %s", peerID)

	// A Kubo daemon on the same machine cannot reliably hairpin through the
	// public NAT address, and Boxo deliberately excludes relay-only limited
	// connections from its Bitswap peer set. Connect over loopback to test the
	// SDK's actual Bitswap serving path independently of public DHT discovery.
	var loopbackAddress string
	for _, address := range node.Status().ListenAddrs {
		if strings.Contains(address, "/ip4/127.0.0.1/") && strings.Contains(address, "/tcp/") {
			loopbackAddress = address
			break
		}
	}
	if loopbackAddress == "" {
		t.Fatal("SDK node has no TCP loopback listen address")
	}
	connectCtx, cancelConnect := context.WithTimeout(context.Background(), 30*time.Second)
	connectResult, err := kuboAPI(connectCtx, "swarm/connect", url.Values{"arg": {loopbackAddress}})
	cancelConnect()
	if err != nil {
		t.Fatalf("Kubo API did not connect directly to SDK: %v: %s", err, connectResult)
	}

	fetchCtx, cancelFetch := context.WithTimeout(context.Background(), 30*time.Second)
	fetched, err := kuboAPI(fetchCtx, "cat", url.Values{"arg": {rawCID}})
	cancelFetch()
	if err != nil {
		stats, _ := node.BitswapStats()
		parsed, _ := cid.Parse(rawCID)
		local, _ := node.store.Has(context.Background(), parsed)
		connected := node.host.Network().Connectedness(kuboPeer)
		wants := node.bitswap.WantlistForPeer(kuboPeer)
		protocols, _ := node.host.Peerstore().GetProtocols(kuboPeer)
		t.Fatalf("Kubo API did not fetch content: %v: %s; local=%t connected=%s wants=%v protocols=%v bitswap=%+v",
			err, fetched, local, connected, wants, protocols, stats)
	}
	if !bytes.Equal(fetched, content) {
		t.Fatalf("Kubo content = %q, want %q", fetched, content)
	}
}

func kuboAPI(ctx context.Context, command string, values url.Values) ([]byte, error) {
	endpoint := "http://127.0.0.1:5001/api/v0/" + command
	if len(values) > 0 {
		endpoint += "?" + values.Encode()
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, nil)
	if err != nil {
		return nil, err
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		return body, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return body, fmt.Errorf("Kubo API status %s", response.Status)
	}
	return body, nil
}
