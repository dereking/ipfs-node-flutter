# Native repository and reliable IPFS publication

## Goals

- A native node is initialized with a required local repository path.
- At most one native IPFS node runs in a process, irrespective of repository
  path. A repository lock also prevents concurrent processes from opening the
  same path.
- Blocks, pins, and content-root metadata survive a node restart.
- Local storage and public publication have distinct, observable outcomes.
- Web remains a local-store/read client and never claims public publication.

## Repository

`PublicNodeConfig` gains a `repositoryPath` that is required by native
backends and optional on Web. The native core creates
an SDK-owned repository beneath that path. It persists blocks, pin records,
and metadata for each locally added content root. Metadata includes the CID,
pin state, creation time, and last publication result. The SDK does not claim
binary compatibility with a Kubo repository, but follows the same operational
semantics: content and pin state survive restart and are periodically
reprovided while the node remains online.

The repository has a lock file. The process-level singleton is checked first;
a second native `start` fails with a typed already-running error even if it
uses another repository. The file lock protects the same repository when a
second process attempts to open it. `stop` and `dispose` release both locks.

## Public-network lifecycle

`addBytes` and `addText` only persist locally. They return a CID after the
block and its metadata have been committed; they make no routing guarantee.

`provide(cid)` waits for a successful DHT provider announcement. It returns a
typed network-not-ready error unless the DHT routing table is usable and the
host advertises either a direct public address or an active circuit-relay
reservation. `addAndProvide` composes local persistence and `provide`.

`networkReady` and repository/publication status are observable through the
platform API. A relay-address change triggers immediate reprovision of all
persisted roots; periodic reprovision remains as a refresh mechanism. Failed
publication is persisted in metadata and returned to callers rather than
silently hidden in a background goroutine.

## Web boundary

Browsers cannot provide the required native repository path, run an inbound
listener, or reliably publish provider records. Web continues to use IndexedDB
for local reads/writes and may retrieve blocks from already connected peers.
It reports no public-publication capability and rejects `provide` and
`addAndProvide` with `UnsupportedCapabilityException`.

## Verification

- Go unit tests cover repository recovery, metadata recovery, process single
  instance, repository file lock, and publication readiness errors.
- Dart tests cover mandatory native repository configuration and typed errors.
- An opt-in integration test starts the SDK node, adds and publishes a CID,
  then uses an independent local Kubo daemon to find and retrieve it.
- Existing Web tests assert the unsupported-publication behavior.
