# Native Repository and Public Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a durable native repository, an in-process singleton, and explicit reliable publication; retain web local read/write only.

**Architecture:** The native core owns an SDK filesystem repository with lock, identity, blocks, and atomic metadata. Explicit publication waits for both DHT routing and reachability. Web implements the same API by rejecting public publication as unsupported.

**Tech Stack:** Flutter/Dart, Dart FFI/C ABI, Go libp2p/Kademlia/Bitswap, local filesystem, Helia/IndexedDB.

---

### Task 1: Contract

**Files:** `packages/ipfs_node_flutter_platform_interface/lib/ipfs_node_platform_interface.dart`, `packages/ipfs_node_flutter/lib/src/ipfs_node.dart`, and their foundation tests.

- [ ] **Step 1: Write failing tests.**

```dart
test('public config requires repositoryPath', () {
  expect(() => NodeConfig.public(repositoryPath: ''), throwsArgumentError);
});
test('facade delegates provide', () async {
  final fake = _RecordingPlatform();
  await IpfsNode(platform: fake).provide('bafkrei-test');
  expect(fake.provided, ['bafkrei-test']);
});
```

- [ ] **Step 2: Run RED.** `flutter test packages/ipfs_node_flutter_platform_interface/test/foundation_test.dart packages/ipfs_node_flutter/test/ipfs_node_test.dart` — expect missing configuration/API symbols.

- [ ] **Step 3: Implement minimal shared API.**

```dart
factory NodeConfig.public({required String repositoryPath, List<String> bootstrapPeers = const []}) =>
    PublicNodeConfig(repositoryPath: repositoryPath, bootstrapPeers: bootstrapPeers);
Future<bool> networkReady() async => _unimplemented('networkReady');
Future<void> provide(String cid, {Duration timeout = const Duration(seconds: 60)}) async => _unimplemented('provide');
Future<IpfsAddResult> addAndProvide(Uint8List bytes, {Duration timeout = const Duration(seconds: 60)}) async => _unimplemented('addAndProvide');
```

Validate nonblank paths, add facade delegates, and update all fake platform implementations.

- [ ] **Step 4: Run GREEN and commit.** `flutter test packages/ipfs_node_flutter_platform_interface/test/foundation_test.dart packages/ipfs_node_flutter/test/ipfs_node_test.dart` — expect PASS. Commit: `feat: define repository and publication API`.

### Task 2: Durable native repository

**Files:** create `native/go/internal/core/repository.go` and `repository_test.go`; modify `native/go/internal/core/core.go` and `core_test.go`.

- [ ] **Step 1: Write failing persistence tests.**

```go
func TestRepositoryRestoresBlocksAndPins(t *testing.T) {
  path := t.TempDir(); first := New()
  requireStart(t, first, PublicConfig{RepositoryPath: path})
  cid, _ := first.AddBytes(context.Background(), []byte("durable"))
  if err := first.Pin(context.Background(), cid); err != nil { t.Fatal(err) }
  _ = first.Stop(); second := New()
  requireStart(t, second, PublicConfig{RepositoryPath: path})
  got, err := second.GetBlock(context.Background(), cid)
  if err != nil || string(got) != "durable" { t.Fatalf("got %q: %v", got, err) }
}
func TestRepositoryRejectsConcurrentOpen(t *testing.T) {
  repo, _ := openRepository(t.TempDir()); defer repo.Close()
  if _, err := openRepository(repo.path); !errors.Is(err, ErrRepositoryLocked) { t.Fatal(err) }
}
```

- [ ] **Step 2: Run RED.** `go test ./internal/core -run 'TestRepository(Restores|Rejects)' -count=1` — expect missing repository code.

- [ ] **Step 3: Implement the repository.**

```go
type repository struct { path string; lock *os.File; store blockstore.Blockstore; metadata repositoryMetadata }
func openRepository(path string) (*repository, error) {
  if strings.TrimSpace(path) == "" { return nil, ErrRepositoryPathRequired }
  if err := os.MkdirAll(filepath.Join(path, "blocks"), 0700); err != nil { return nil, err }
  lock, err := acquireExclusiveLock(filepath.Join(path, "repo.lock"))
  if err != nil { return nil, ErrRepositoryLocked }
  // Load metadata.json and a CID-addressed filesystem blockstore.
}
```

Implement the blockstore operations used by Bitswap using atomic CID-named files. Persist metadata (roots, pins, last publication) and the libp2p identity atomically. Open the repository before host construction, reuse store/key/pins, and close it on every error and `Stop`. Update existing core tests to supply `t.TempDir()`.

- [ ] **Step 4: Run GREEN and commit.** `go test ./internal/core -count=1` — expect PASS. Commit: `feat: persist native IPFS repository`.

### Task 3: One native core per process

**Files:** `native/go/internal/core/core.go`, `core_test.go`, `native/go/cmd/ipfs_node_core/main.go`, `packages/ipfs_node_flutter_native/lib/src/ipfs_node_flutter_native.dart`, and native adapter tests.

- [ ] **Step 1: Write the failing process-singleton test.**

```go
func TestOnlyOneNativeCoreRunsPerProcess(t *testing.T) {
  first, second := New(), New()
  requireStart(t, first, PublicConfig{RepositoryPath: t.TempDir()})
  defer first.Stop()
  if err := second.Start(PublicConfig{RepositoryPath: t.TempDir()}); !errors.Is(err, ErrNodeAlreadyRunning) { t.Fatal(err) }
}
```

- [ ] **Step 2: Run RED.** `go test ./internal/core -run TestOnlyOneNativeCoreRunsPerProcess -count=1` — expect two cores to start.

- [ ] **Step 3: Implement guard and typed FFI error.**

```go
var runningNativeCore atomic.Bool
func acquireProcessNode() error {
  if !runningNativeCore.CompareAndSwap(false, true) { return ErrNodeAlreadyRunning }
  return nil
}
func releaseProcessNode() { runningNativeCore.Store(false) }
```

Acquire after validation and release on every failed start and `Stop`. Add ABI code/mapping plus `NativeNodeAlreadyRunningException`.

- [ ] **Step 4: Run GREEN and commit.** `go test ./internal/core -run 'TestOnlyOneNativeCoreRunsPerProcess|TestRepository' -count=1 && flutter test packages/ipfs_node_flutter_native/test/foundation_test.dart` — expect PASS. Commit: `feat: enforce native IPFS process singleton`.

### Task 4: Explicit ready-network publication

**Files:** `native/go/internal/core/core.go`, `core_test.go`, `native/go/cmd/ipfs_node_core/main.go`, `native/go/dist/libipfs_node_core.h`, and native Dart adapter/test files.

- [ ] **Step 1: Write failing publication tests.**

```go
func TestProvideRequiresNetworkReadiness(t *testing.T) {
  node := New(); requireStart(t, node, PublicConfig{RepositoryPath: t.TempDir()})
  cid, _ := node.AddBytes(context.Background(), []byte("local"))
  if err := node.Provide(context.Background(), cid); !errors.Is(err, ErrNetworkNotReady) { t.Fatal(err) }
}
```

- [ ] **Step 2: Run RED.** `go test ./internal/core -run TestProvideRequiresNetworkReadiness -count=1` — expect `Provide` absent.

- [ ] **Step 3: Implement the synchronous path.**

```go
func (core *Core) NetworkReady() bool {
  status := core.Status()
  return status.DhtReady && (hasPublicAddress(status.ListenAddrs) || status.RelayReady)
}
func (core *Core) Provide(ctx context.Context, rawCID string) error {
  if !core.NetworkReady() { return ErrNetworkNotReady }
  parsed, err := cid.Parse(rawCID); if err != nil { return err }
  if err := core.dht.Provide(ctx, parsed, true); err != nil { return err }
  return core.repo.recordPublication(parsed.String(), time.Now(), "")
}
```

Add `network_ready`, `provide`, and `add_and_provide` C ABI methods plus Dart bindings. `AddBytes` only persists; it never hides a background provide. Reprovide successfully announced roots on a relay/address change and periodically thereafter.

- [ ] **Step 4: Run GREEN, regenerate ABI, commit.** `go test ./internal/core -run TestProvide -count=1 && make build-host && make verify-abi` — expect PASS. Commit: `feat: require ready network for IPFS publication`.

### Task 5: Web boundary, example, docs, and Kubo validation

**Files:** web platform and tests, `README.md`, `docs/USAGE.md`, `example/lib/main.dart`, `example/lib/feature_checks.dart`, example tests, and `native/go/internal/core/core_test.go`.

- [ ] **Step 1: Write failing web test.**

```dart
test('web allows local add but rejects public publication', () async {
  final node = IpfsNodeFlutterWeb(bridge: bridge);
  await node.start(testPublicConfig);
  final added = await node.addBytes(Uint8List.fromList([1]));
  expect(() => node.provide(added.cid), throwsA(isA<UnsupportedCapabilityException>()));
});
```

- [ ] **Step 2: Run RED.** `flutter test packages/ipfs_node_flutter_web/test/foundation_test.dart` — expect unimplemented publication behavior.

- [ ] **Step 3: Implement web rejection and complete the example.** Return `UnsupportedCapabilityException(Capability.publicPublication)` from web `provide` and `addAndProvide`; never advertise the capability. Make the example use one application-support repository-backed node and display readiness separately from local add. Add an opt-in `IPFS_KUBO_INTEGRATION=1` Go test that waits for readiness, calls `AddAndProvide`, then requires `ipfs routing findprovs <cid>` and `ipfs block get <cid>` to find the SDK peer and exact data.

- [ ] **Step 4: Run verification and commit.**

Run: `(cd packages/ipfs_node_flutter_platform_interface && flutter test && flutter analyze lib test) && (cd packages/ipfs_node_flutter && flutter test && flutter analyze lib test) && (cd packages/ipfs_node_flutter_native && flutter test && flutter analyze lib test) && (cd packages/ipfs_node_flutter_web && flutter test && flutter analyze lib test) && (cd native/go && go test ./internal/core && make verify-abi) && (cd example && flutter test test/ipfs_node_functionality_test.dart && flutter analyze lib test)`

Expected: all commands exit 0. When a Kubo daemon is reachable, separately run `IPFS_KUBO_INTEGRATION=1 go test -timeout 3m -run TestKuboCanReadExplicitlyPublishedCID -v ./internal/core`. Commit: `test: verify published SDK content with Kubo`.
