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

The following capabilities are intentionally not exposed from the common SDK
API until later phases:

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
(cd packages/ipfs_node_flutter_web && flutter test --platform chrome)
(cd packages/ipfs_node_flutter_web/example && flutter run -d chrome)
```

Run the Go lifecycle and ABI checks from `native/go`:

```sh
(cd native/go && go test -race ./internal/core && make verify-abi)
```
