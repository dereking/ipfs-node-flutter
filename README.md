# ipfs-node-flutter

`ipfs-node-flutter` is a Flutter IPFS node SDK workspace for Android, iOS,
macOS, Windows, Linux, and web. This foundation phase only starts and stops a
backend and reports its capabilities.

The following capabilities are intentionally not exposed until later phases:

- content add, get, and pin operations;
- public DHT networking;
- private swarm-key enforcement;
- IPNS;
- PubSub; and
- remote pinning.

## Tests

Run Flutter tests from each package directory:

```sh
flutter test
```

Run the Go core tests from `native/go`:

```sh
go test ./internal/core
```
