# ipfs-node-flutter

`ipfs-node-flutter` is a Flutter IPFS node SDK workspace for Android, iOS,
macOS, Windows, Linux, and web. The native foundation currently implements a
local, thread-safe lifecycle state machine and does not create a libp2p host
yet. The Web backend starts a real Helia/js-libp2p browser node with an
IndexedDB blockstore and supports its experimental `addBytes`/`getBytes`
UnixFS bridge.

With `NodeConfig.public()` the browser backend uses the WSS addresses
advertised by the public Amino DHT bootstrap peers. A caller can override them
with `PublicNodeConfig.bootstrapPeers`, but every supplied address must be
browser-dialable (normally `/wss`, `/webtransport`, or a relay route). The
bootstrap connection makes the node part of the public libp2p network; this
foundation deliberately does **not** run a browser DHT, provider routing, or
automatic relay reservation yet. Consequently, a Web `getBytes` call is
guaranteed for local content and may retrieve content from an already
connected peer, but it does not promise public-CID discovery.

Browser limitations are explicit: it has no raw TCP/UDP listener, no inbound
TCP/QUIC reachability, no mDNS, and no private swarm-key support. It can use
WebRTC, WebTransport (where available), WSS, and circuit relay transports.
Private browser networks require a later authenticated-relay design; the
backend rejects private swarm-key configuration today.

The common `ipfs_node_flutter` package currently exposes only lifecycle,
configuration, status, and capability APIs. The web implementation also has
an **experimental backend-specific** `addBytes` / `getBytes` bridge for its
real Helia node; it is not yet part of the common cross-platform API or a
promise of public-CID discovery.

The following common SDK capabilities are intentionally not exposed until
later phases:

- cross-platform content add, get, and pin operations;
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

Run the complete foundation matrix from the repository root. The native ABI
check builds the macOS host library, compiles a C client against the packaged
header, and runs that client. The browser test requires Chrome to be
available to Flutter.

```sh
(cd packages/ipfs_node_flutter && flutter test && flutter analyze lib test)
(cd packages/ipfs_node_flutter_platform_interface && flutter test && flutter analyze lib test)
(cd packages/ipfs_node_flutter_native && flutter test && flutter analyze lib test)
(cd packages/ipfs_node_flutter_web && flutter test --platform chrome && flutter analyze lib test)
(cd native/go && go test -race ./internal/core && make verify-abi)
```

The next feature gate is a native node that can connect to Kubo in an
integration test. Only after that passes may the common API add `add` / `get`;
UnixFS, CAR, local pinning, public/private routing, IPNS, PubSub, and remote
pinning remain later work.
