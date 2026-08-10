# Strict Public Provider Publication Design

## Goal

Make public content publication truthful and durable: `provide` and
`addAndProvide` return successfully only after remote public DHT peers confirm
that they hold this SDK node's provider record. Keep a separate asynchronous
API for Kubo-style eventual publication, persist publication work across
restarts, maintain records through periodic reprovides, and demonstrate the
whole path with an independent Kubo node.

## Scope

This design changes public-network publication, publication metadata and
status, the Flutter API surface, and the complete Example. It preserves the
existing process-wide single SDK instance, repository identity, blockstore,
Bitswap server, private-network behavior, pinning, IPNS, bootstrap and swarm
APIs.

It does not claim permanent global availability. DHT peers and relay
reservations can disappear. A strict success means that the content is local,
the SDK node currently has a public direct or relay address, and a quorum of
remote DHT peers has confirmed the provider record at the time the call
returns.

## Success levels

Publication is split into explicit levels instead of one ambiguous boolean:

1. `local`: every block required by the returned root CID is durable in the
   configured repository.
2. `pending`: the root is in the persistent provide set and will be retried.
3. `confirmed`: enough remote DHT peers returned this node as a provider.
4. `degraded`: a previously confirmed root is due for reprovide, the node lost
   public reachability, or a reprovide attempt failed.
5. `failed`: a strict publication attempt exhausted its deadline without
   reaching the confirmation threshold. The root remains local and queued.

`lastPublished` means the last remotely confirmed publication. An attempted
write never advances it.

## Public API behavior

### `addBytes`

Stores content locally and records the root. It does not require network
readiness and does not enqueue publication.

### `startProviding`

Adds an existing local root to the durable provide set and schedules an
immediate background attempt. It returns after the scheduling metadata is
durable. This is the Kubo-style eventual API for bulk or offline-friendly
workflows.

### `provide`

Requires the root to exist locally and the public node to have a non-empty DHT
routing table plus a public direct address or relay reservation. It schedules
the root durably, performs a strict publication within the supplied timeout,
and returns only after remote confirmation. On failure it records the error,
keeps the root pending, and returns a typed request error.

### `addAndProvide`

Calls `addBytes`, then strict `provide`. If publication fails, the method
returns the CID together with publication failure information rather than
discarding the durable local result. The Flutter result type therefore exposes
the CID and byte count even for the partial-success case.

### Publication status

A new query returns per-root status containing:

- CID and state;
- added time;
- last attempt time;
- last confirmed publication time;
- attempt count;
- target peer count;
- successful write count;
- remote confirmation count and required confirmation count;
- last error;
- next retry time.

Existing metadata is migrated in place. Historical `lastPublished` entries
without confirmation evidence become `pending`, because the old SDK could not
prove remote acceptance.

## Strict DHT publication

The implementation uses the existing libp2p Host and Kademlia DHT; it does not
create a verifier host or a second SDK instance.

For a CID:

1. Confirm the root block exists in the local blockstore.
2. Snapshot the current filtered public/relay addresses. Refuse publication if
   no usable address is available.
3. Run `GetClosestPeers` for the CID multihash.
4. Use the DHT's exported message sender with `ProtocolMessenger` to send an
   `ADD_PROVIDER` containing the SDK Peer ID and filtered addresses to each
   target peer. Record every per-peer error instead of discarding it.
5. Query peers whose write completed with `GET_PROVIDERS` and count only peers
   whose response contains the SDK Peer ID.
6. Require `max(1, ceil(targetPeerCount * 0.20))` confirmations. This follows
   the current DHT provider subsystem's minimum reachable-peer ratio while
   remaining usable in small private test swarms.
7. Only then mark the root `confirmed` and advance `lastPublished`.

Each peer operation has a bounded timeout derived from the caller's deadline.
The aggregate error reports target, write-success, confirmed and required
counts plus a bounded sample of peer errors. No private key, content bytes or
sensitive swarm-key material appears in diagnostics.

## Durable provide set and reprovide

Every `startProviding` or strict `provide` first writes pending state to the
repository metadata. Startup reloads this set and schedules all pending,
failed, degraded and previously confirmed roots.

Confirmed roots are reprovided every six hours, comfortably inside the public
DHT provider-record lifetime. Failed attempts use bounded exponential backoff
with jitter, starting at 30 seconds and capped at 30 minutes. A successful
confirmation resets the backoff. Shutdown preserves queue state; startup
resumes it.

Only one background provider worker runs per SDK instance. It serializes
metadata transitions while network RPCs run without holding the Core mutex.
Stopping the node cancels in-flight work and closes the worker before closing
the DHT, host or repository.

## Relay and network status

Relay readiness is derived from the live advertised addresses used for
provider records, not from a startup snapshot. Status includes the active relay
addresses and a timestamp for the latest observation. Public `networkReady`
means:

- the DHT routing table is non-empty; and
- the current filtered addresses contain either a public direct address or a
  circuit-relay address.

Publication status remains independent: a node can be network-ready while a
specific CID is pending or failed.

## Example behavior

The complete Example shows four independent indicators:

- DHT ready;
- relay/public address ready;
- provider state for the selected CID;
- external Kubo verification state.

The content workflow demonstrates local add, asynchronous `startProviding`,
strict `provide`, strict `addAndProvide`, status refresh, retry and error
details. The Kubo verifier executes bounded `routing findprovs` and `cat`
operations, requires the SDK Peer ID in the provider result, compares returned
bytes with the original content, and reports discovery and transfer timings.
Kubo remains an external test tool and is never embedded into the SDK.

Web keeps read-only public retrieval. It exposes publication as unsupported and
does not display strict publication controls.

## Error handling

- Missing local root: fail without enqueuing an invalid item.
- DHT or relay/public address not ready: persist pending state, return
  `network not ready`, and let the worker retry.
- Partial DHT writes below quorum: persist exact counters and a safe error,
  return failure, and retry later.
- Context cancellation or timeout: persist the failed attempt without marking
  it confirmed.
- Metadata write failure: do not report scheduling or publication success.
- Reprovide failure: retain the previous confirmation timestamp but move state
  to `degraded` until the next confirmed attempt.

## Testing

Tests are added before implementation and cover:

- old metadata migration does not trust historical `lastPublished`;
- a local root is required before publication;
- failed remote writes do not update `lastPublished`;
- remote `GET_PROVIDERS` confirmation is required;
- the 20% confirmation threshold and small-swarm minimum;
- error counters and safe diagnostics;
- pending work survives repository restart;
- confirmed roots reprovide and failed roots back off;
- live relay addresses drive readiness and status;
- Flutter models and native ABI preserve partial `addAndProvide` results;
- Example controls and status rendering;
- a process-level public integration test that publishes a unique block, uses
  an independently running Kubo API to find the SDK Peer ID, and retrieves the
  exact bytes. The public test is opt-in for ordinary unit runs but mandatory
  for release verification.

## Compatibility

Existing `provide` callers retain the method name but receive stricter failure
semantics. `addAndProvide` gains explicit partial-success data; callers that
only read successful results remain source-compatible where possible. Metadata
migration is automatic and does not delete blocks, pins, identity or private
network configuration.
