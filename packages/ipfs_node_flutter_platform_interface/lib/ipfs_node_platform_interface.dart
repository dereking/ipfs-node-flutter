import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The transport and protocol features a backend can provide.
enum Capability {
  inboundListen,
  tcp,
  quic,
  webRtc,
  webTransport,
  dhtRouting,
  mdns,
  privateSwarmKey,
  unixfs,
  car,
  ipns,
  pubsub,
  remotePinning,
  providerRouting,
  publicPublication,
}

/// A capability requested by the caller is unavailable on this backend.
///
/// This lives in the platform contract so platform packages can report the
/// same typed failure without depending on the public facade package.
sealed class IpfsNodeException implements Exception {
  const IpfsNodeException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class UnsupportedCapabilityException extends IpfsNodeException {
  UnsupportedCapabilityException(this.capability)
      : super('Unsupported capability: $capability');

  final Capability capability;
}

final class CapabilitySet {
  CapabilitySet(Iterable<Capability> capabilities)
      : _capabilities = Set.unmodifiable(capabilities);

  const CapabilitySet.empty() : _capabilities = const {};

  final Set<Capability> _capabilities;

  bool contains(Capability capability) => _capabilities.contains(capability);

  Set<Capability> get values => _capabilities;

  @override
  bool operator ==(Object other) =>
      other is CapabilitySet &&
      _capabilities.length == other._capabilities.length &&
      _capabilities.containsAll(other._capabilities);

  @override
  int get hashCode => Object.hashAllUnordered(_capabilities);
}

sealed class NodeConfig {
  const NodeConfig._();

  factory NodeConfig.public({
    String? repositoryPath,
    List<String> bootstrapPeers = const [],
  }) =>
      PublicNodeConfig(
        repositoryPath: repositoryPath,
        bootstrapPeers: bootstrapPeers,
      );

  factory NodeConfig.private({
    String? repositoryPath,
    required List<int> swarmKey,
    List<String> bootstrapPeers = const [],
    List<String> relayPeers = const [],
    Set<String> allowedPeerIds = const {},
  }) =>
      PrivateNodeConfig(
        repositoryPath: repositoryPath,
        swarmKey: swarmKey,
        bootstrapPeers: bootstrapPeers,
        relayPeers: relayPeers,
        allowedPeerIds: allowedPeerIds,
      );
}

final class PublicNodeConfig extends NodeConfig {
  PublicNodeConfig({
    String? repositoryPath,
    List<String> bootstrapPeers = const [],
  })  : _repositoryPath = repositoryPath,
        _bootstrapPeers = List.unmodifiable(bootstrapPeers),
        super._();

  final String? _repositoryPath;
  final List<String> _bootstrapPeers;

  /// Native backends require a non-empty local filesystem path. Browser
  /// backends use IndexedDB and therefore do not require one.
  String? get repositoryPath => _repositoryPath;
  List<String> get bootstrapPeers => _bootstrapPeers;

  @override
  bool operator ==(Object other) =>
      other is PublicNodeConfig &&
      _repositoryPath == other._repositoryPath &&
      _listsEqual(_bootstrapPeers, other._bootstrapPeers);

  @override
  int get hashCode =>
      Object.hash(_repositoryPath, Object.hashAll(_bootstrapPeers));
}

final class PrivateNodeConfig extends NodeConfig {
  PrivateNodeConfig({
    String? repositoryPath,
    required List<int> swarmKey,
    List<String> bootstrapPeers = const [],
    List<String> relayPeers = const [],
    Set<String> allowedPeerIds = const {},
  })  : _repositoryPath = repositoryPath,
        _swarmKey = List.unmodifiable(swarmKey),
        _bootstrapPeers = List.unmodifiable(bootstrapPeers),
        _relayPeers = List.unmodifiable(relayPeers),
        _allowedPeerIds = Set.unmodifiable(allowedPeerIds),
        super._() {
    if (swarmKey.length != 32) {
      throw ArgumentError.value(
        swarmKey,
        'swarmKey',
        'must contain exactly 32 bytes',
      );
    }
  }

  final String? _repositoryPath;
  final List<int> _swarmKey;
  final List<String> _bootstrapPeers;
  final List<String> _relayPeers;
  final Set<String> _allowedPeerIds;

  /// Native backends require a non-empty local filesystem path. Browser
  /// backends reject private-network configurations.
  String? get repositoryPath => _repositoryPath;
  List<int> get swarmKey => _swarmKey;
  List<String> get bootstrapPeers => _bootstrapPeers;
  List<String> get relayPeers => _relayPeers;
  Set<String> get allowedPeerIds => _allowedPeerIds;

  @override
  bool operator ==(Object other) =>
      other is PrivateNodeConfig &&
      _repositoryPath == other._repositoryPath &&
      _listsEqual(_swarmKey, other._swarmKey) &&
      _listsEqual(_bootstrapPeers, other._bootstrapPeers) &&
      _listsEqual(_relayPeers, other._relayPeers) &&
      _setsEqual(_allowedPeerIds, other._allowedPeerIds);

  @override
  int get hashCode => Object.hash(
        _repositoryPath,
        Object.hashAll(_swarmKey),
        Object.hashAll(_bootstrapPeers),
        Object.hashAll(_relayPeers),
        Object.hashAllUnordered(_allowedPeerIds),
      );
}

bool _listsEqual<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _setsEqual<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

/// Result of storing bytes in the local node.
final class IpfsAddResult {
  const IpfsAddResult({required this.cid, required this.bytes});

  final String cid;
  final int bytes;

  @override
  bool operator ==(Object other) =>
      other is IpfsAddResult && cid == other.cid && bytes == other.bytes;

  @override
  int get hashCode => Object.hash(cid, bytes);
}

/// How a content root is pinned.
enum IpfsPinType { direct, recursive }

/// A locally pinned content root.
final class IpfsPinInfo {
  const IpfsPinInfo({required this.cid, required this.type, this.pinnedAt});

  final String cid;
  final IpfsPinType type;
  final DateTime? pinnedAt;

  @override
  bool operator ==(Object other) =>
      other is IpfsPinInfo &&
      cid == other.cid &&
      type == other.type &&
      pinnedAt == other.pinnedAt;

  @override
  int get hashCode => Object.hash(cid, type, pinnedAt);
}

/// A libp2p peer known to the node.
final class IpfsPeerInfo {
  const IpfsPeerInfo({required this.id, this.addrs = const []});

  final String id;
  final List<String> addrs;

  @override
  bool operator ==(Object other) =>
      other is IpfsPeerInfo &&
      id == other.id &&
      _listsEqual(addrs, other.addrs);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(addrs));
}

/// Aggregate bitswap client and server counters.
final class IpfsBitswapStats {
  const IpfsBitswapStats({
    required this.blocksSent,
    required this.blocksReceived,
    required this.dataSent,
    required this.dataReceived,
    required this.wantlist,
    required this.messagesSent,
    required this.messagesReceived,
  });

  final int blocksSent;
  final int blocksReceived;
  final int dataSent;
  final int dataReceived;
  final int wantlist;
  final int messagesSent;
  final int messagesReceived;

  @override
  bool operator ==(Object other) =>
      other is IpfsBitswapStats &&
      blocksSent == other.blocksSent &&
      blocksReceived == other.blocksReceived &&
      dataSent == other.dataSent &&
      dataReceived == other.dataReceived &&
      wantlist == other.wantlist &&
      messagesSent == other.messagesSent &&
      messagesReceived == other.messagesReceived;

  @override
  int get hashCode => Object.hash(
        blocksSent,
        blocksReceived,
        dataSent,
        dataReceived,
        wantlist,
        messagesSent,
        messagesReceived,
      );
}

/// A local IPNS key.
final class IpfsKeyInfo {
  const IpfsKeyInfo({required this.name, required this.peerId});

  final String name;
  final String peerId;

  @override
  bool operator ==(Object other) =>
      other is IpfsKeyInfo && name == other.name && peerId == other.peerId;

  @override
  int get hashCode => Object.hash(name, peerId);
}

enum NodeLifecycle { stopped, starting, running, degraded, stopping, failed }

final class NodeStatus {
  const NodeStatus({
    required this.lifecycle,
    this.safeDiagnostic,
    this.peerId,
    this.listenAddrs = const [],
    this.connectedPeers = const [],
    this.bootstrapErrors = const [],
    this.relayAddrs = const [],
    this.relayReady = false,
    this.routingTableSize = 0,
    this.dhtReady = false,
  });

  const NodeStatus.running({
    String? safeDiagnostic,
    String? peerId,
    List<String> listenAddrs = const [],
    List<String> connectedPeers = const [],
    List<String> bootstrapErrors = const [],
    List<String> relayAddrs = const [],
    bool relayReady = false,
    int routingTableSize = 0,
    bool dhtReady = false,
  }) : this(
          lifecycle: NodeLifecycle.running,
          safeDiagnostic: safeDiagnostic,
          peerId: peerId,
          listenAddrs: listenAddrs,
          connectedPeers: connectedPeers,
          bootstrapErrors: bootstrapErrors,
          relayAddrs: relayAddrs,
          relayReady: relayReady,
          routingTableSize: routingTableSize,
          dhtReady: dhtReady,
        );

  final NodeLifecycle lifecycle;
  final String? safeDiagnostic;
  final String? peerId;
  final List<String> listenAddrs;
  final List<String> connectedPeers;
  final List<String> bootstrapErrors;

  /// Live circuit-relay addresses for this node (only meaningful on native
  /// backends; web browsers are reached through their own transports).
  final List<String> relayAddrs;

  /// Whether at least one circuit-relay reservation is active, so peers can
  /// dial this node through NAT.
  final bool relayReady;

  /// Number of peers in the DHT routing table.
  final int routingTableSize;

  /// Whether the DHT routing table has peers, i.e. lookups and provider
  /// announcements can reach the network.
  final bool dhtReady;

  @override
  bool operator ==(Object other) =>
      other is NodeStatus &&
      lifecycle == other.lifecycle &&
      safeDiagnostic == other.safeDiagnostic &&
      peerId == other.peerId &&
      _listsEqual(listenAddrs, other.listenAddrs) &&
      _listsEqual(connectedPeers, other.connectedPeers) &&
      _listsEqual(bootstrapErrors, other.bootstrapErrors) &&
      _listsEqual(relayAddrs, other.relayAddrs) &&
      relayReady == other.relayReady &&
      routingTableSize == other.routingTableSize &&
      dhtReady == other.dhtReady;

  @override
  int get hashCode => Object.hash(
        lifecycle,
        safeDiagnostic,
        peerId,
        Object.hashAll(listenAddrs),
        Object.hashAll(connectedPeers),
        Object.hashAll(bootstrapErrors),
        Object.hashAll(relayAddrs),
        relayReady,
        routingTableSize,
        dhtReady,
      );
}

abstract base class IpfsNodePlatform extends PlatformInterface {
  IpfsNodePlatform() : super(token: _token);

  static final Object _token = Object();
  static IpfsNodePlatform _instance = _DefaultIpfsNodePlatform();

  static IpfsNodePlatform get instance => _instance;

  static set instance(IpfsNodePlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Creates an isolated backend for one [IpfsNode] instance.
  ///
  /// Stateless platform implementations may return themselves. Backends that
  /// own native resources must override this method.
  IpfsNodePlatform create() => this;

  Future<void> start(NodeConfig config);

  Future<void> stop();

  /// Releases resources associated with this backend.
  Future<void> dispose() => stop();

  Future<NodeStatus> status();

  Future<CapabilitySet> capabilities();

  /// Retrieves and verifies one raw IPFS block by CID.
  Future<Uint8List> getBlock(
    String cid, {
    Duration timeout = const Duration(seconds: 180),
  }) async =>
      _unimplemented('getBlock');

  /// Stores bytes as an IPFS content root and returns its CID.
  Future<IpfsAddResult> addBytes(Uint8List bytes) async =>
      _unimplemented('addBytes');

  /// Whether this node can announce content through its configured router.
  Future<bool> networkReady() async => _unimplemented('networkReady');

  /// Announces an already-local content root through the configured router.
  Future<void> provide(
    String cid, {
    Duration timeout = const Duration(seconds: 60),
  }) async =>
      _unimplemented('provide');

  /// Stores bytes locally and waits for a provider announcement.
  Future<IpfsAddResult> addAndProvide(
    Uint8List bytes, {
    Duration timeout = const Duration(seconds: 60),
  }) async =>
      _unimplemented('addAndProvide');

  /// Pins a content root so its block stays available locally.
  Future<void> pin(String cid) async => _unimplemented('pin');

  /// Removes a local pin for a content root.
  Future<void> unpin(String cid) async => _unimplemented('unpin');

  /// Lists the locally pinned content roots.
  Future<List<IpfsPinInfo>> listPins() async => _unimplemented('listPins');

  /// Returns the peers with open connections to this node.
  Future<List<IpfsPeerInfo>> swarmPeers() async => _unimplemented('swarmPeers');

  /// Dials a peer encoded as a p2p multiaddr.
  Future<void> swarmConnect(String multiaddr) async =>
      _unimplemented('swarmConnect');

  /// Closes all connections to a peer.
  Future<void> swarmDisconnect(String peerId) async =>
      _unimplemented('swarmDisconnect');

  /// Returns the configured bootstrap multiaddrs.
  Future<List<String>> bootstrapList() async => _unimplemented('bootstrapList');

  /// Validates and records a bootstrap multiaddr.
  Future<void> bootstrapAdd(String multiaddr) async =>
      _unimplemented('bootstrapAdd');

  /// Removes a bootstrap multiaddr.
  Future<void> bootstrapRemove(String multiaddr) async =>
      _unimplemented('bootstrapRemove');

  /// Returns the current bitswap counters.
  Future<IpfsBitswapStats> bitswapStats() async =>
      _unimplemented('bitswapStats');

  /// Searches the DHT for peers advertising a content root.
  Future<List<IpfsPeerInfo>> findProviders(
    String cid, {
    Duration timeout = const Duration(seconds: 30),
  }) async =>
      _unimplemented('findProviders');

  /// Locates a peer on the DHT and returns its addresses.
  Future<IpfsPeerInfo> findPeer(
    String peerId, {
    Duration timeout = const Duration(seconds: 30),
  }) async =>
      _unimplemented('findPeer');

  /// Publishes a content root under this node's IPNS name.
  Future<String> publishName(
    String cid, {
    Duration timeout = const Duration(seconds: 60),
  }) async =>
      _unimplemented('publishName');

  /// Resolves an IPNS name to a content path.
  Future<String> resolveName(
    String name, {
    Duration timeout = const Duration(seconds: 60),
  }) async =>
      _unimplemented('resolveName');

  /// Returns the local IPNS keys.
  Future<List<IpfsKeyInfo>> listKeys() async => _unimplemented('listKeys');

  Never _unimplemented(String operation) => throw UnimplementedError(
      'IpfsNodePlatform.$operation() has not been implemented.');
}

final class _DefaultIpfsNodePlatform extends IpfsNodePlatform {
  @override
  Future<CapabilitySet> capabilities() async => _unimplemented('capabilities');

  @override
  Future<void> start(NodeConfig config) async => _unimplemented('start');

  @override
  Future<NodeStatus> status() async => _unimplemented('status');

  @override
  Future<void> stop() async {
    // Stopping an unregistered node is a no-op so teardown never crashes when
    // no platform implementation was installed.
  }
}
