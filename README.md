# ipfs-node-flutter

`ipfs-node-flutter` is a Flutter IPFS node SDK workspace for Android, iOS,
macOS, Windows, Linux, and web. The current foundation implements a local,
thread-safe native lifecycle state machine and reports no protocol or
transport capabilities. It does not create a libp2p host yet.

The following capabilities are intentionally not exposed until later phases:

- content add, get, and pin operations;
- public DHT networking;
- private swarm-key enforcement;
- IPNS;
- PubSub; and
- remote pinning.

## Native C ABI

`native/go/dist/libipfs_node_core.h` is the single distributed C ABI header
created by `make build-host`. It composes cgo's generated declarations with
stable return codes for lifecycle calls. `ipfs_node_start` receives either
`{"network":"public"}` or
`{"network":"private","swarmKey":"<base64>"}`. Results from
`ipfs_node_status` and `ipfs_node_capabilities` must be released with
`ipfs_node_free_string`.

## Foundation validation

These commands validate the foundation contracts; protocol APIs are added in
later phases.

```sh
(cd packages/ipfs_node_flutter && flutter test)
(cd packages/ipfs_node_flutter_platform_interface && flutter test)
(cd packages/ipfs_node_flutter_native && flutter test)
(cd packages/ipfs_node_flutter_web && flutter test)
```

Run the Go lifecycle and ABI checks from `native/go`:

```sh
(cd native/go && go test -race ./internal/core && make verify-abi)
```
