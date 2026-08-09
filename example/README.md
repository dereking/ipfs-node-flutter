# macOS public IPFS example

This Flutter application exercises the common `ipfs_node_flutter` API through
the native Go backend. On launch it:

1. starts a real libp2p node with `NodeConfig.public()`;
2. connects to the default public IPFS bootstrap peers;
3. displays its Peer ID and connected-peer count;
4. retrieves a documented raw CID through the Amino DHT and Bitswap; and
5. verifies that the returned bytes are exactly `Hello IPFS\n`.

The Xcode project builds `native/go`, embeds `libipfs_node_core.dylib` in the
application Frameworks directory, and signs the library with the app build
identity. Debug/Profile and Release entitlements allow inbound and outbound
network connections.

```sh
flutter run -d macos
```

The green success state and the `IPFS_PUBLIC_TEST_PASS` log line mean that the
SDK—not a gateway or an external Kubo process—retrieved the block from public
IPFS.

Run the Dart functionality tests without building the macOS application:

```sh
flutter test test/ipfs_node_functionality_test.dart
IPFS_PUBLIC_INTEGRATION=1 flutter test test/ipfs_node_functionality_test.dart
```

The first command covers native lifecycle, capabilities, error mapping, and
per-node identity isolation. The second also connects to public IPFS and
retrieves the fixed CID through DHT and Bitswap.
