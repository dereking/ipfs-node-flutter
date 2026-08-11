# Complete public/private IPFS example

This Flutter application demonstrates the complete implemented
`ipfs_node_flutter` API through one process-wide SDK instance. Its four pages
cover:

1. public/private configuration and persistent repository selection;
2. content add/get/pin, strict provider confirmation, durable publication
   queue, retry counters, and persisted publication status;
3. swarm, bootstrap, Bitswap, DHT provider and peer routing;
4. IPNS, capability diagnostics, and an ordered run-all workflow.

Private mode accepts a 32-byte PSK, private bootstrap peers, and optional relay
and Peer-ID allowlist values. Switching mode stops the current node before
starting the replacement, preserving the one-node-per-process invariant.

The Xcode project builds `native/go`, embeds `libipfs_node_core.dylib` in the
application Frameworks directory, and signs the library with the app build
identity. Debug/Profile and Release entitlements allow inbound and outbound
network connections.

The Windows CMake build (`example/windows/CMakeLists.txt`) runs
`go build -buildmode=c-shared` for `ipfs_node_core.dll` and installs it next to
the executable, so `flutter run -d windows` works out of the box when a Go
toolchain with cgo support (e.g. mingw-w64 gcc) is on `PATH`.

```sh
flutter run -d macos
flutter run -d windows
```

Kubo is not bundled or controlled by the Example. It remains an optional
external acceptance tool.

On web, provider publication controls are disabled because a browser node
cannot offer the native inbound/provider guarantees. Local IndexedDB
add/read/pin and supported routing queries remain available.

Run the Dart functionality tests without building the macOS application:

```sh
flutter test test/ipfs_node_functionality_test.dart
IPFS_PUBLIC_INTEGRATION=1 flutter test test/ipfs_node_functionality_test.dart
```

The first command covers native lifecycle, capabilities, error mapping,
process-singleton enforcement, persistent identity, and private configuration.
The second also connects to public IPFS and retrieves the fixed CID through DHT
and Bitswap.

The deterministic Go integration test starts a second private SDK node in a
child process and verifies PSK isolation plus DHT provider/Bitswap retrieval:

```sh
(cd ../native/go && go test ./internal/core -run TestPrivateNetworkAcrossProcesses -v)
```
