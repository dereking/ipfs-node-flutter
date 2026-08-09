# ipfs-node-flutter

`ipfs-node-flutter` is a Flutter IPFS node SDK workspace for Android, iOS,
macOS, Windows, Linux, and web. Its current state is a scaffold only; it does
not yet implement backend start/stop or capability reporting. Those are the
next foundation steps.

The following capabilities are intentionally not exposed until later phases:

- content add, get, and pin operations;
- public DHT networking;
- private swarm-key enforcement;
- IPNS;
- PubSub; and
- remote pinning.

## Scaffold validation

These commands validate the empty foundation scaffolds; production APIs will be
added in later phases.

```sh
(cd packages/ipfs_node_flutter && flutter test)
(cd packages/ipfs_node_flutter_platform_interface && flutter test)
(cd packages/ipfs_node_flutter_native && flutter test)
(cd packages/ipfs_node_flutter_web && flutter test)
```

Run the Go core scaffold test from `native/go`:

```sh
(cd native/go && go test ./internal/core)
```
