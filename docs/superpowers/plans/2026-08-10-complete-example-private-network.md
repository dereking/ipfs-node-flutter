# Complete Example and Private Network Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the native private IPFS network implementation and turn `example` into a single-instance, four-page demonstration of every implemented SDK operation.

**Architecture:** Public and private native nodes share one repository/libp2p/DHT/Bitswap/IPNS startup path. Private mode adds a libp2p PSK, private peer sources, and optional peer gating. One Example controller switches modes through stop/configure/start and exposes capability-driven pages plus a deterministic run-all workflow.

**Tech Stack:** Flutter/Dart federated plugin, Dart FFI, Go c-shared ABI, go-libp2p v0.49, Boxo v0.42, LevelDB, Flutter widget tests, Go tests.

---

## File Map

- `packages/ipfs_node_flutter_platform_interface/lib/ipfs_node_platform_interface.dart`: private repository configuration and generic provider-routing capability.
- `native/go/internal/core/core.go`: shared public/private startup, readiness, capabilities, and lifecycle cleanup.
- `native/go/internal/core/peer_gater.go`: optional private peer allowlist implementation.
- `native/go/internal/core/core_test.go`: private startup, PSK, readiness, and persistence tests.
- `native/go/cmd/ipfs_node_core/main.go`: complete private configuration C ABI decoding.
- `native/go/test/abi_runtime_client.c`: ABI private-start coverage.
- `packages/ipfs_node_flutter_native/lib/src/ipfs_node_flutter_native.dart`: Dart-to-ABI configuration encoding and capability mapping.
- `example/lib/example_node_configuration.dart`: public/private form state, PSK parsing/generation, repository selection.
- `example/lib/example_operation_runner.dart`: ordered run-all workflow and operation log model.
- `example/lib/main.dart`: one controller and four-page application shell.
- `example/lib/pages/*.dart`: focused configuration, content, routing, and IPNS/diagnostics pages.
- Relevant package and Example tests: contract, FFI, controller, operation runner, and widget behavior.

### Task 1: Extend the Cross-Platform Configuration Contract

**Files:**
- Modify: `packages/ipfs_node_flutter_platform_interface/lib/ipfs_node_platform_interface.dart`
- Modify: `packages/ipfs_node_flutter_platform_interface/test/foundation_test.dart`
- Modify: `packages/ipfs_node_flutter/test/ipfs_node_test.dart`

- [ ] **Step 1: Write failing configuration and capability tests**

Add these assertions:

```dart
test('private config preserves repository and peer controls', () {
  final config = NodeConfig.private(
    repositoryPath: '/tmp/private-repo',
    swarmKey: List<int>.filled(32, 7),
    bootstrapPeers: const ['/ip4/127.0.0.1/tcp/4001/p2p/QmBootstrap'],
    relayPeers: const ['/ip4/127.0.0.1/tcp/4002/p2p/QmRelay'],
    allowedPeerIds: const {'QmBootstrap'},
  ) as PrivateNodeConfig;
  expect(config.repositoryPath, '/tmp/private-repo');
  expect(config.swarmKey, hasLength(32));
});

test('provider routing is a distinct capability', () {
  expect(Capability.values, contains(Capability.providerRouting));
});
```

- [ ] **Step 2: Run tests and confirm RED**

Run: `flutter test packages/ipfs_node_flutter_platform_interface/test/foundation_test.dart`

Expected: compilation fails because `repositoryPath` and `providerRouting` do not exist.

- [ ] **Step 3: Implement the contract**

Add `Capability.providerRouting`, add optional `repositoryPath` to
`NodeConfig.private`, store it defensively in `PrivateNodeConfig`, include it in
equality/hashCode, and document that Native requires a non-empty path while Web
rejects private mode.

- [ ] **Step 4: Format and verify the contract**

Run:

```sh
dart format packages/ipfs_node_flutter_platform_interface/lib/ipfs_node_platform_interface.dart packages/ipfs_node_flutter_platform_interface/test/foundation_test.dart packages/ipfs_node_flutter/test/ipfs_node_test.dart
flutter test packages/ipfs_node_flutter_platform_interface/test/foundation_test.dart
flutter test packages/ipfs_node_flutter/test/ipfs_node_test.dart
flutter analyze packages/ipfs_node_flutter_platform_interface/lib packages/ipfs_node_flutter_platform_interface/test
```

Expected: all tests pass and analyze reports no issues.

- [ ] **Step 5: Commit**

```sh
git add packages/ipfs_node_flutter_platform_interface packages/ipfs_node_flutter/test/ipfs_node_test.dart
git commit -m "feat: complete private node configuration contract"
```

### Task 2: Implement Shared Native Public and Private Startup

**Files:**
- Create: `native/go/internal/core/peer_gater.go`
- Modify: `native/go/internal/core/core.go`
- Modify: `native/go/internal/core/core_test.go`

- [ ] **Step 1: Write failing private-start tests**

Add tests that require a real host and repository:

```go
func TestPrivateStartCreatesProtectedPersistentNode(t *testing.T) {
	config := PrivateConfig{
		RepositoryPath: t.TempDir(),
		SwarmKey:       bytes.Repeat([]byte{7}, 32),
	}
	node := New()
	if err := node.Start(config); err != nil { t.Fatal(err) }
	t.Cleanup(func() { _ = node.Stop() })
	if node.host == nil || node.store == nil || node.dht == nil {
		t.Fatal("private node did not initialize the shared stack")
	}
	if node.networkMode != networkPrivate { t.Fatal("private mode not recorded") }
}

func TestPrivateConfigRequiresRepositoryAnd32BytePSK(t *testing.T) {
	if err := New().Start(PrivateConfig{SwarmKey: make([]byte, 32)}); !errors.Is(err, ErrRepositoryPathRequired) {
		t.Fatalf("error = %v", err)
	}
	if err := New().Start(PrivateConfig{RepositoryPath: t.TempDir(), SwarmKey: []byte{1}}); !errors.Is(err, ErrInvalidPrivateSwarmKey) {
		t.Fatalf("error = %v", err)
	}
}
```

- [ ] **Step 2: Run focused Go tests and confirm RED**

Run: `go test ./internal/core -run 'TestPrivate(Start|Config)' -count=1`

Expected: private startup has no host and new fields/types are missing.

- [ ] **Step 3: Add shared network configuration**

Introduce exact internal shapes:

```go
type networkMode uint8
const (
	networkPublic networkMode = iota
	networkPrivate
)

type PrivateConfig struct {
	RepositoryPath string
	SwarmKey       []byte
	BootstrapPeers []string
	RelayPeers     []string
	AllowedPeerIDs []string
}

type networkConfig struct {
	mode            networkMode
	repositoryPath  string
	swarmKey        []byte
	bootstrapPeers  []string
	relayPeers      []string
	allowedPeerIDs  []string
}
```

Map both public and private configs to `networkConfig` and call one
`startNetwork`. Build common libp2p options from persistent identity. In private
mode append `libp2p.PrivateNetwork(pnet.PSK(config.swarmKey))`; never inject
public fallback bootstrap peers.

- [ ] **Step 4: Implement optional peer gating and relay configuration**

Create a `peerAllowlistGater` implementing every
`connmgr.ConnectionGater` method. Empty allowlist permits all PSK-authenticated
peers. A non-empty allowlist permits the node itself, configured bootstrap and
relay peers, and explicit IDs. Parse relay multiaddrs to `peer.AddrInfo` and use
`libp2p.EnableAutoRelayWithStaticRelays` in private mode; retain public relay
discovery in public mode.

- [ ] **Step 5: Implement mode-specific readiness and capabilities**

Store `networkMode` on `Core` and implement:

```go
func (core *Core) NetworkReady() bool {
	status := core.Status()
	if core.mode() == networkPrivate {
		return status.DhtReady && len(status.ConnectedPeers) > 0
	}
	return status.DhtReady && (status.RelayReady || hasPublicAddress(core.hostAddrs()))
}
```

Public capabilities include `providerRouting` and `publicPublication`; private
capabilities include `privateSwarmKey` and `providerRouting` but not
`publicPublication`.

- [ ] **Step 6: Verify cleanup and persistence**

Extend tests to stop/restart a private repository, assert stable Peer ID and
local block/pin recovery, and assert the singleton flag is released after PSK,
bootstrap, repository, or host initialization errors.

- [ ] **Step 7: Run and commit**

Run:

```sh
gofmt -w internal/core/core.go internal/core/core_test.go internal/core/peer_gater.go
go test ./internal/core -count=1
```

Expected: PASS.

```sh
git add native/go/internal/core
git commit -m "feat: implement persistent private IPFS nodes"
```

### Task 3: Complete the C ABI and Native Dart Adapter

**Files:**
- Modify: `native/go/cmd/ipfs_node_core/main.go`
- Modify: `native/go/abi_contract_test.go`
- Modify: `native/go/test/abi_runtime_client.c`
- Modify: `packages/ipfs_node_flutter_native/lib/src/ipfs_node_flutter_native.dart`
- Modify: `packages/ipfs_node_flutter_native/test/foundation_test.dart`

- [ ] **Step 1: Write failing ABI/adapter tests**

Capture a private start request and assert it contains:

```dart
expect(request, containsPair('network', 'private'));
expect(request, containsPair('repositoryPath', '/tmp/private-repo'));
expect(request, containsPair('bootstrapPeers', bootstrapPeers));
expect(request, containsPair('relayPeers', relayPeers));
expect(request, containsPair('allowedPeerIds', ['12D3Allowed']));
expect(base64Decode(request['swarmKey'] as String), List<int>.filled(32, 9));
```

Update the C runtime client to start a 32-byte-PSK private node with a temporary
repository and require non-null status/capability JSON.

- [ ] **Step 2: Run tests and confirm RED**

Run:

```sh
flutter test packages/ipfs_node_flutter_native/test/foundation_test.dart
go test ./... -run TestABIContract -count=1
```

Expected: private fields are absent or private start lacks a host.

- [ ] **Step 3: Encode every private field**

Extend `startRequest` with `relayPeers` and `allowedPeerIds`, then map all fields
to `core.PrivateConfig`. In Dart, encode `PrivateNodeConfig` as:

```dart
{
  'network': 'private',
  'repositoryPath': repositoryPath,
  'swarmKey': base64Encode(swarmKey),
  'bootstrapPeers': bootstrapPeers,
  'relayPeers': relayPeers,
  'allowedPeerIds': allowedPeerIds.toList()..sort(),
}
```

Reject a missing native private repository with a typed configuration error
before entering FFI.

- [ ] **Step 4: Rebuild and verify ABI**

Run:

```sh
gofmt -w cmd/ipfs_node_core/main.go abi_contract_test.go
make verify-abi
flutter test packages/ipfs_node_flutter_native/test/foundation_test.dart
flutter analyze packages/ipfs_node_flutter_native/lib packages/ipfs_node_flutter_native/test
```

Expected: ABI client and Dart tests pass.

- [ ] **Step 5: Commit**

```sh
git add native/go packages/ipfs_node_flutter_native
git commit -m "feat: bridge private node configuration through native ABI"
```

### Task 4: Add Deterministic Private-Network Integration Coverage

**Files:**
- Create: `native/go/internal/core/testhelper/main.go`
- Create: `native/go/internal/core/private_integration_test.go`

- [ ] **Step 1: Write the parent integration test**

The test builds the helper, starts it with repository path, PSK, and a machine-
readable ready-file path, then starts the in-process node using the helper's
announced multiaddr. It must assert matching keys connect, content is provided,
the other process retrieves the exact bytes, and mismatched keys cannot
connect. All child processes are terminated in `t.Cleanup`.

- [ ] **Step 2: Implement the helper protocol**

Use JSON lines over stdin/stdout:

```json
{"type":"ready","peerId":"12D3KooWTestPeer","addrs":["/ip4/127.0.0.1/tcp/41001/p2p/12D3KooWTestPeer"]}
{"type":"get","cid":"bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244"}
{"type":"content","cid":"bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244","data":"SGVsbG8gSVBGUwo="}
```

The helper starts one `Core`, reports loopback-dialable addresses, accepts get
commands, and stops on EOF or SIGTERM.

- [ ] **Step 3: Run the integration test**

Run: `go test ./internal/core -run TestPrivateNetworkAcrossProcesses -count=1 -v`

Expected: PASS without internet or Kubo.

- [ ] **Step 4: Commit**

```sh
git add native/go/internal/core/testhelper native/go/internal/core/private_integration_test.go
git commit -m "test: verify private IPFS routing across processes"
```

### Task 5: Add Example Configuration and Operation Models

**Files:**
- Create: `example/lib/example_node_configuration.dart`
- Create: `example/lib/example_operation_runner.dart`
- Create: `example/test/example_node_configuration_test.dart`
- Create: `example/test/example_operation_runner_test.dart`

- [ ] **Step 1: Write failing configuration tests**

Cover 64-character hex parsing, secure generation, masked display,
fingerprinting, public/private repository paths, and rejection of invalid key
length/characters. Assert private paths are stable for the same key and differ
for different keys.

- [ ] **Step 2: Implement `ExampleNodeConfiguration`**

Expose immutable public/private fields and:

```dart
NodeConfig build(String applicationSupportPath);
String get repositoryPath;
String get maskedSwarmKey;
String get swarmKeyFingerprint;
static Uint8List parseSwarmKey(String hex);
static String generateSwarmKeyHex(Random secureRandom);
```

Use `Random.secure`. Derive the repository fingerprint with a local 64-bit
FNV-1a function over all 32 key bytes and render all 16 hexadecimal digits.
This value is only a stable directory discriminator; it is never used for
authentication. Do not expose any substring of the PSK in the directory name.

- [ ] **Step 3: Write failing run-all tests**

Use a fake `IpfsNode` backend and assert exact operation order, elapsed-time log
entries, waiting results when `networkReady` is false, continuation after a
non-dependent failure, and cancellation when the node stops.

- [ ] **Step 4: Implement `ExampleOperationRunner`**

Define `ExampleOperationState` (`running`, `passed`, `waiting`, `failed`) and
immutable log entries. Execute local add/get/pin/list first; execute
provide/findProviders/IPNS only when ready; always finish with Bitswap stats.

- [ ] **Step 5: Verify and commit**

Run:

```sh
dart format example/lib/example_node_configuration.dart example/lib/example_operation_runner.dart example/test/example_node_configuration_test.dart example/test/example_operation_runner_test.dart
flutter test example/test/example_node_configuration_test.dart
flutter test example/test/example_operation_runner_test.dart
```

Expected: PASS.

```sh
git add example/lib/example_node_configuration.dart example/lib/example_operation_runner.dart example/test
git commit -m "feat: add example configuration and operation workflow"
```

### Task 6: Build the Four-Page Example Console

**Files:**
- Create: `example/lib/pages/node_configuration_page.dart`
- Create: `example/lib/pages/content_repository_page.dart`
- Create: `example/lib/pages/network_routing_page.dart`
- Create: `example/lib/pages/ipns_diagnostics_page.dart`
- Create: `packages/ipfs_node_flutter/lib/ui/ipfs_capability_panel.dart`
- Create: `packages/ipfs_node_flutter/lib/ui/ipfs_find_peer_panel.dart`
- Create: `packages/ipfs_node_flutter/lib/ui/ipfs_operation_log_panel.dart`
- Modify: `packages/ipfs_node_flutter/lib/ui/ipfs_node_ui.dart`
- Modify: `example/lib/main.dart`
- Modify: `packages/ipfs_node_flutter/test/ui_test.dart`
- Create: `example/test/complete_example_test.dart`

- [ ] **Step 1: Write failing reusable-panel widget tests**

Test capability supported/unavailable text, find-peer success/error, and
operation-log running/passed/waiting/failed states.

- [ ] **Step 2: Implement the three focused reusable panels**

Each panel accepts data/callbacks; none creates an `IpfsNode`. Export them from
`ipfs_node_ui.dart`. Keep all async button state inside the relevant panel and
show typed errors as selectable text.

- [ ] **Step 3: Write failing complete-Example widget tests**

Assert four navigation destinations, a disabled Start button before repository
resolution, public start, private form validation, safe public-to-private mode
switch, every API control, Web unsupported labels, and run-all summary.

- [ ] **Step 4: Implement the app shell and pages**

`main.dart` owns exactly one controller, selected configuration, live status,
capabilities, readiness timer, session CID history, and operation runner. Pages
receive state and callbacks. Remove the Kubo panel from normal navigation.

Use a single periodic refresh while running; cancel it before stop/dispose.
Refresh status, capabilities, readiness, pins, peers, and Bitswap independently
so one failed diagnostic does not erase other usable data.

- [ ] **Step 5: Verify Example and UI**

Run:

```sh
dart format example/lib example/test packages/ipfs_node_flutter/lib/ui packages/ipfs_node_flutter/test/ui_test.dart
flutter test packages/ipfs_node_flutter/test/ui_test.dart
flutter test example/test/complete_example_test.dart
flutter test example/test/ipfs_node_functionality_test.dart
flutter analyze packages/ipfs_node_flutter/lib packages/ipfs_node_flutter/test
flutter analyze example/lib example/test
```

Expected: all tests pass and analyze reports no issues.

- [ ] **Step 6: Commit**

```sh
git add packages/ipfs_node_flutter example
git commit -m "feat: complete the IPFS example console"
```

### Task 7: Documentation and Final Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/USAGE.md`
- Modify: `example/README.md`

- [ ] **Step 1: Update documentation**

Document private repository requirements, 32-byte PSK format, private
bootstrap isolation, readiness differences, single-instance mode switching,
the four Example pages, Web limitations, and the separation between Example
features and optional Kubo acceptance tests.

- [ ] **Step 2: Run final focused verification**

Run:

```sh
go test ./internal/core -count=1
make verify-abi
flutter test packages/ipfs_node_flutter_platform_interface/test/foundation_test.dart
flutter test packages/ipfs_node_flutter/test/ipfs_node_test.dart
flutter test packages/ipfs_node_flutter/test/ui_test.dart
flutter test packages/ipfs_node_flutter_native/test/foundation_test.dart
flutter test packages/ipfs_node_flutter_web/test/foundation_test.dart
flutter test example/test/example_node_configuration_test.dart
flutter test example/test/example_operation_runner_test.dart
flutter test example/test/complete_example_test.dart
flutter test example/test/ipfs_node_functionality_test.dart
flutter analyze packages/ipfs_node_flutter_platform_interface/lib packages/ipfs_node_flutter_platform_interface/test
flutter analyze packages/ipfs_node_flutter/lib packages/ipfs_node_flutter/test
flutter analyze packages/ipfs_node_flutter_native/lib packages/ipfs_node_flutter_native/test
flutter analyze packages/ipfs_node_flutter_web/lib packages/ipfs_node_flutter_web/test
flutter analyze example/lib example/test
git diff --check
```

Expected: every command exits zero. Public internet and Kubo acceptance tests
remain skipped unless their explicit environment flags are set.

- [ ] **Step 3: Commit documentation**

```sh
git add README.md docs/USAGE.md example/README.md
git commit -m "docs: document complete public and private example"
```
