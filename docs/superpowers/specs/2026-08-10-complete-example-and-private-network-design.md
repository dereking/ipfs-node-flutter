# Complete Example and Private Network Design

## Goal

Turn the Flutter example into a complete, capability-driven demonstration of
every public SDK operation on one process-wide node. Complete the native
private-network backend so private mode is functional instead of reporting a
false running state.

Kubo is not part of the example. It remains an optional external acceptance
tool for checking public provider discovery and retrieval.

## Architecture

The example owns one `IpfsNodeController` and therefore one native node. A
network-mode change always follows this sequence:

1. Stop the running node.
2. Release its repository lock and network resources.
3. Build the selected public or private configuration.
4. Start the same controller with the new configuration.

Public and private native nodes use one shared Go initialization path for the
persistent repository, identity, libp2p host, Bitswap, DHT, IPNS, bootstrap,
relay support, status, and shutdown. Private mode changes only the network
boundary and peer sources: it installs a libp2p private-network protector from
the swarm key and never falls back to public IPFS bootstrap peers.

Web continues to reject private mode with
`UnsupportedCapabilityException(Capability.privateSwarmKey)` and must not
report a successful private start.

## Configuration

Native public and private nodes both require a stable repository path:

```dart
NodeConfig.public(
  repositoryPath: publicRepositoryPath,
  bootstrapPeers: publicBootstrapPeers,
);

NodeConfig.private(
  repositoryPath: privateRepositoryPath,
  swarmKey: swarmKey,
  bootstrapPeers: privateBootstrapPeers,
  relayPeers: privateRelayPeers,
  allowedPeerIds: allowedPeerIds,
);
```

Only the swarm key and private bootstrap list are fundamental private-network
parameters. Relay peers and the peer allowlist remain optional advanced
controls.

The example represents the PSK as exactly 32 bytes and displays it as 64
hexadecimal characters. It can generate a secure random value or parse a
user-supplied value. Dart passes raw bytes through the existing base64 JSON ABI
encoding. Logs, diagnostics, and exceptions never include the complete key.

Repositories are separated by mode and private-network identity:

- Public: `<application-support>/ipfs-node/public`
- Private: `<application-support>/ipfs-node/private/<key-fingerprint>`

The fingerprint is a non-secret hash prefix. Reusing the same private key
selects the same repository, blocks, pins, metadata, and stable Peer ID.

## Native Private Network

`PrivateConfig` gains repository, bootstrap, relay, and allowlist values. The
C ABI and Dart native adapter pass every value without dropping fields.

The shared Go start path performs these steps:

1. Open and lock the persistent repository.
2. load or create the persistent identity.
3. Construct the libp2p host, adding the PSK protector in private mode.
4. Apply the optional peer allowlist to inbound and outbound connections.
5. Initialize the DHT, Bitswap, and IPNS services.
6. Connect only to the selected mode's bootstrap and relay peers.
7. Restore pins and successfully published roots for periodic reprovide.
8. Start readiness observation and periodic reprovide.

Any failure closes all partially created resources, releases the process-wide
singleton flag, and leaves a safe failed or stopped state.

## Capability and Readiness Semantics

Add the generic `providerRouting` capability:

- Native public: `providerRouting` and `publicPublication`
- Native private: `providerRouting` only
- Web: neither capability

Public readiness remains:

```text
DHT ready AND (relay reservation ready OR public direct address available)
```

Private readiness is:

```text
DHT ready AND at least one private peer connected
```

Private peers may communicate on a LAN or a configured private relay, so a
public address is not a private-network requirement.

`addBytes` and `addText` always mean durable local storage. `provide` and
`addAndProvide` require the selected network's readiness and return a typed
failure when routing is not ready. Successfully provided roots persist and are
restored for periodic reprovide.

## Example User Interface

The example has four pages backed by the same controller.

### Node and Configuration

- Public/private mode selector
- Persistent repository path
- Private PSK input, generation, validation, and fingerprint
- Bootstrap editor
- Collapsible relay and peer-allowlist controls
- Start, stop, refresh, and safe mode switching
- Peer ID, lifecycle, addresses, connections, DHT, relay, and diagnostics
- Capability matrix showing supported, unsupported, and temporarily
  unavailable features

### Content and Repository

- Add text or binary content locally
- Add and provide content
- Reprovide an existing local CID
- Retrieve a block by CID
- Pin, unpin, and list pins
- Session CID history
- Restart checks demonstrating durable blocks and pins

### Network and Routing

- Swarm peer list
- Connect and disconnect
- Bootstrap list, add, and remove
- Bitswap statistics and wantlist
- Find providers
- Find peer
- Live network-readiness status
- Public publication wording in public mode and private routing wording in
  private mode

### IPNS, Capabilities, and Diagnostics

- List local IPNS keys
- Publish an IPNS name
- Resolve an IPNS name
- Operation log with duration and typed failure
- A run-all action executing, in dependency order: add, get, pin, list pins,
  provide, find providers, IPNS publish/resolve, and Bitswap statistics

Steps requiring another peer are reported as waiting for an external condition
when no suitable bootstrap or connected peer exists. The example never marks
such a step successful merely because the local call was attempted.

The Kubo command panel is removed from the example's normal workflow. Kubo
checks remain in separately gated external tests.

## Error Handling

The UI and platform adapters preserve distinct errors for:

- Invalid private key length or encoding
- Missing native repository path
- Repository lock contention
- A second SDK instance in the same process
- Bootstrap or private peer connection failure
- DHT or relay/readiness failure
- Unsupported Web capabilities
- Operation timeout

The configuration panel masks secret material in logs. Mode-switch failures do
not retain a half-started node or stale readiness state.

## Testing

### Go Core

- Shared public/private initialization and cleanup
- PSK isolation: matching keys connect; mismatched keys do not
- Private bootstrap and optional relay/allowlist behavior
- Private readiness and provider routing
- Persistent identity, blocks, pins, and published-root restoration
- Process singleton release after success and every startup failure

Private end-to-end tests start the second SDK node in a child process, keeping
the one-node-per-process invariant.

### Dart and FFI

- Private repository, swarm key, bootstrap, relay, and allowlist ABI encoding
- Capability mapping for public, private, and Web
- Typed startup, readiness, and routing errors
- Public API delegation for every demonstrated operation

### Example

- Four-page rendering and navigation
- Public/private configuration validation
- Safe stop-and-restart mode switching
- Every operation panel and its loading, success, waiting, and failure states
- Run-all ordering and summary
- Native/Web capability-specific presentation

Public-network and external-Kubo acceptance tests remain opt-in so normal tests
are deterministic and do not require internet access or a local Kubo daemon.

## Non-Goals

- Bundling, installing, or controlling Kubo from the example
- Running two native SDK nodes in the same process
- Implementing private swarm support in browsers
- Adding CAR, PubSub, or remote-pinning APIs that are not currently implemented
  by the SDK
