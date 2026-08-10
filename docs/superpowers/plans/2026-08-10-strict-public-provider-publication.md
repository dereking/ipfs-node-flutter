# Strict Public Provider Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make public provider publication remotely confirmed, durably retried, accurately reported through Flutter, and verifiable end-to-end with an independent Kubo node.

**Architecture:** Keep the existing single Core/libp2p Host. Add a repository-backed publication state machine, publish with the DHT's exported message sender, and confirm records by querying the remote DHT peers that accepted each write. Expose scheduling and status through the native ABI and Flutter APIs, then drive the same workflow from the complete Example.

**Tech Stack:** Go 1.25, go-libp2p-kad-dht, Boxo blockstore/Bitswap, C ABI/FFI, Dart/Flutter, Kubo HTTP API.

---

## File structure

- `native/go/internal/core/publication.go`: strict DHT publisher, quorum calculation, safe diagnostics and retry scheduling.
- `native/go/internal/core/repository.go`: durable publication metadata and migration.
- `native/go/internal/core/core.go`: lifecycle integration and public methods.
- `native/go/internal/core/publication_test.go`: focused state-machine and remote-confirmation tests.
- `native/go/internal/core/public_integration_test.go`: opt-in independent Kubo verification.
- `native/go/cmd/ipfs_node_core/main.go`: C ABI endpoints and partial-result JSON.
- `packages/ipfs_node_flutter_platform_interface/lib/ipfs_node_platform_interface.dart`: public models and abstract APIs.
- `packages/ipfs_node_flutter_native/lib/src/ipfs_node_flutter_native.dart`: native JSON decoding and ABI bindings.
- `packages/ipfs_node_flutter/lib/src/ipfs_node.dart`: SDK facade.
- `packages/ipfs_node_flutter/lib/ui/ipfs_publication_status_panel.dart`: per-CID publication display.
- `packages/ipfs_node_flutter/lib/ui/ipfs_content_add_panel.dart`: local, scheduled and strict add actions.
- `example/lib/example_operation_runner.dart`: complete operation sequence.
- `example/lib/complete_example_page.dart`: periodic publication status and Kubo validation wiring.
- Corresponding existing test files under each package and `example/test/`.

### Task 1: Durable publication state

**Files:**
- Modify: `native/go/internal/core/repository.go`
- Create: `native/go/internal/core/publication.go`
- Create: `native/go/internal/core/publication_test.go`

- [ ] **Step 1: Write failing repository migration and transition tests**

Add tests that load legacy metadata containing only `lastPublished`, expect it to migrate to `pending`, and exercise explicit attempt, confirmed, degraded and failed transitions. The desired model is:

```go
type PublicationState string

const (
    PublicationLocal     PublicationState = "local"
    PublicationPending   PublicationState = "pending"
    PublicationConfirmed PublicationState = "confirmed"
    PublicationDegraded  PublicationState = "degraded"
    PublicationFailed    PublicationState = "failed"
)

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
```

- [ ] **Step 2: Run the focused Go tests and verify RED**

Run: `go test ./internal/core -run 'TestPublicationMetadata|TestLegacyPublicationMigration'`

Expected: compilation or assertion failure because the publication states and transitions do not exist.

- [ ] **Step 3: Implement the metadata model and atomic transitions**

Preserve roots, pins and timestamps. Add repository methods `schedulePublication`, `recordPublicationAttempt`, `recordPublicationConfirmed`, `recordPublicationFailure`, `publicationStatus` and `publicationQueue`. Legacy `lastPublished` without confirmation counters migrates to pending without deleting the historical timestamp from disk until the next save.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `go test ./internal/core -run 'TestPublicationMetadata|TestLegacyPublicationMigration'`

Expected: PASS.

### Task 2: Strict remote DHT confirmation and durable retry

**Files:**
- Modify: `native/go/internal/core/publication.go`
- Modify: `native/go/internal/core/core.go`
- Modify: `native/go/internal/core/publication_test.go`
- Modify: `native/go/internal/core/core_test.go`
- Modify: `native/go/internal/core/public_integration_test.go`

- [ ] **Step 1: Write failing publisher behavior tests**

Use a small in-process DHT swarm and the real blockstore. Cover missing local root, no usable advertised address, all writes failing, writes succeeding without `GET_PROVIDERS` confirmation, quorum success, and quorum calculation:

```go
func requiredProviderConfirmations(targets int) int {
    if targets <= 0 { return 0 }
    required := (targets + 4) / 5
    if required < 1 { return 1 }
    return required
}
```

Assert failed attempts never advance `LastPublished` and confirmed attempts do.

- [ ] **Step 2: Run publisher tests and verify RED**

Run: `go test ./internal/core -run 'TestStrictProvide|TestRequiredProviderConfirmations|TestStartProviding'`

Expected: FAIL because strict publication and scheduling APIs are missing.

Also add the opt-in independent Kubo test before production changes. Start the
SDK with a persistent test repository, add unique bytes, publish, query Kubo
until it returns the SDK Peer ID, retrieve the CID and compare exact bytes.
The already reproduced old behavior is Provider lookup/retrieval timeout; keep
the test skipped unless `IPFS_PUBLIC_INTEGRATION=1` is set.

- [ ] **Step 3: Implement strict publication**

Create a `dhtMessenger` interface around `PutProviderAddrs` and `GetProviders`. In production build it from `dht_pb.NewProtocolMessenger(kad.MessageSender())`. Obtain closest peers from `kad.GetClosestPeers`, send the provider record with `kad.FilteredAddrs()`, then count only remote responses containing the local Peer ID. Return a typed `PublicationError` with safe counters and a bounded error sample when confirmations are below quorum.

- [ ] **Step 4: Implement scheduling and lifecycle**

Add `StartProviding`, `PublicationStatus` and `ListPublicationStatuses`. Keep strict `Provide`; make `AddAndProvide` return its durable CID with a publication error. Start one cancellable worker after bootstrap, reload queued roots, reprovide confirmed roots at six hours, and retry failures from 30 seconds up to 30 minutes. Stop the worker before DHT/host/repository shutdown.

- [ ] **Step 5: Run publisher and existing core tests and verify GREEN**

Run: `go test ./internal/core`

Expected: PASS, including private-network integration behavior.

### Task 3: Native ABI and Flutter API

**Files:**
- Modify: `native/go/cmd/ipfs_node_core/main.go`
- Modify: `packages/ipfs_node_flutter_platform_interface/lib/ipfs_node_platform_interface.dart`
- Modify: `packages/ipfs_node_flutter_native/lib/src/ipfs_node_flutter_native.dart`
- Modify: `packages/ipfs_node_flutter/lib/src/ipfs_node.dart`
- Modify tests in the same packages.

- [ ] **Step 1: Write failing Dart contract tests**

Require `PublicationStatus`, `PublicationState`, `startProviding`, `publicationStatus`, `listPublicationStatuses`, and partial `addAndProvide` errors carrying `IpfsAddResult`:

```dart
final class IpfsPublicationException implements Exception {
  const IpfsPublicationException({required this.result, required this.message});
  final IpfsAddResult result;
  final String message;
}
```

- [ ] **Step 2: Run Dart tests and verify RED**

Run: `flutter test test/foundation_test.dart` in `packages/ipfs_node_flutter_platform_interface`, then `flutter test test/ipfs_node_test.dart` in `packages/ipfs_node_flutter`.

Expected: compilation failure for the new public types and methods.

- [ ] **Step 3: Add ABI endpoints and JSON models**

Export `ipfs_node_start_providing`, `ipfs_node_publication_status`, and `ipfs_node_list_publication_statuses`. Make `ipfs_node_add_and_provide` include `cid`, `bytes`, publication counters and `error` on partial failure. Decode all fields defensively in the native backend.

- [ ] **Step 4: Implement facade and web behavior**

Delegate the new methods through `IpfsNode`. Web throws `UnsupportedCapabilityException(Capability.publicPublication)` for all publication mutations while retaining public read/routing APIs.

- [ ] **Step 5: Run package tests and verify GREEN**

Run the platform-interface, native, facade and web focused test files. Expected: PASS.

### Task 4: Complete Example integration

**Files:**
- Modify: `packages/ipfs_node_flutter/lib/ui/ipfs_publication_status_panel.dart`
- Modify: `packages/ipfs_node_flutter/lib/ui/ipfs_content_add_panel.dart`
- Modify: `packages/ipfs_node_flutter/lib/ui/ipfs_cid_publication_panel.dart`
- Modify: `example/lib/example_operation_runner.dart`
- Modify: `example/lib/complete_example_page.dart`
- Modify: `example/lib/pages/content_repository_page.dart`
- Modify: `example/lib/pages/network_routing_page.dart`
- Modify relevant widget and operation-runner tests.

- [ ] **Step 1: Write failing widget and runner tests**

Assert the Example exposes local add, queued provide, strict provide, strict add-and-provide, per-CID state/counters, manual retry, Relay/DHT readiness separately, and Kubo provider/content verification.

- [ ] **Step 2: Run the focused Flutter tests and verify RED**

Run: `flutter test test/ui_test.dart` in `packages/ipfs_node_flutter` and `flutter test test/example_operation_runner_test.dart test/widget_test.dart` in `example`.

Expected: FAIL because the new controls and states are absent.

- [ ] **Step 3: Implement SDK UI and Example workflow**

Refresh publication state every three seconds with node status. Display pending/confirmed/degraded/failed distinctly and never infer publication from Relay readiness. Keep publication controls hidden/disabled on web.

- [ ] **Step 4: Harden Kubo verification**

Use bounded commands/API calls. Require `routing findprovs` output to contain the SDK Peer ID before `cat`, compare exact bytes, and report discovery and retrieval durations separately.

- [ ] **Step 5: Run widget and Example tests and verify GREEN**

Run the focused commands from Step 2. Expected: PASS.

### Task 5: End-to-end verification and documentation

**Files:**
- Modify: `native/go/internal/core/public_integration_test.go`
- Modify: `README.md`
- Modify: `example/README.md`

- [ ] **Step 1: Document publication semantics and operational diagnostics**

Document local versus pending versus confirmed, `startProviding` versus strict `provide`, repository migration, single-instance behavior, Kubo validation commands, and the impossibility of permanent global availability guarantees.

- [ ] **Step 2: Run final verification**

Run Go core tests, focused Flutter tests, `dart analyze` for changed packages/files, `dart format` on changed Dart files, `gofmt` on changed Go files, and the opt-in Kubo public integration test. Expected: all commands exit 0; no test failures or analyzer errors.

- [ ] **Step 3: Review the final diff**

Run `git diff --check`, inspect every changed file against the design, and request code review before declaring completion.
