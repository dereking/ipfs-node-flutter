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

  factory NodeConfig.public({List<String> bootstrapPeers = const []}) =>
      PublicNodeConfig(bootstrapPeers: bootstrapPeers);

  factory NodeConfig.private({
    required List<int> swarmKey,
    List<String> bootstrapPeers = const [],
    List<String> relayPeers = const [],
    Set<String> allowedPeerIds = const {},
  }) =>
      PrivateNodeConfig(
        swarmKey: swarmKey,
        bootstrapPeers: bootstrapPeers,
        relayPeers: relayPeers,
        allowedPeerIds: allowedPeerIds,
      );
}

final class PublicNodeConfig extends NodeConfig {
  PublicNodeConfig({List<String> bootstrapPeers = const []})
      : _bootstrapPeers = List.unmodifiable(bootstrapPeers),
        super._();

  final List<String> _bootstrapPeers;

  List<String> get bootstrapPeers => _bootstrapPeers;

  @override
  bool operator ==(Object other) =>
      other is PublicNodeConfig &&
      _listsEqual(_bootstrapPeers, other._bootstrapPeers);

  @override
  int get hashCode => Object.hashAll(_bootstrapPeers);
}

final class PrivateNodeConfig extends NodeConfig {
  PrivateNodeConfig({
    required List<int> swarmKey,
    List<String> bootstrapPeers = const [],
    List<String> relayPeers = const [],
    Set<String> allowedPeerIds = const {},
  })  : _swarmKey = List.unmodifiable(swarmKey),
        _bootstrapPeers = List.unmodifiable(bootstrapPeers),
        _relayPeers = List.unmodifiable(relayPeers),
        _allowedPeerIds = Set.unmodifiable(allowedPeerIds),
        super._() {
    if (swarmKey.isEmpty) {
      throw ArgumentError.value(swarmKey, 'swarmKey', 'must not be empty');
    }
  }

  final List<int> _swarmKey;
  final List<String> _bootstrapPeers;
  final List<String> _relayPeers;
  final Set<String> _allowedPeerIds;

  List<int> get swarmKey => _swarmKey;
  List<String> get bootstrapPeers => _bootstrapPeers;
  List<String> get relayPeers => _relayPeers;
  Set<String> get allowedPeerIds => _allowedPeerIds;

  @override
  bool operator ==(Object other) =>
      other is PrivateNodeConfig &&
      _listsEqual(_swarmKey, other._swarmKey) &&
      _listsEqual(_bootstrapPeers, other._bootstrapPeers) &&
      _listsEqual(_relayPeers, other._relayPeers) &&
      _setsEqual(_allowedPeerIds, other._allowedPeerIds);

  @override
  int get hashCode => Object.hash(
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

enum NodeLifecycle { stopped, starting, running, degraded, stopping, failed }

final class NodeStatus {
  const NodeStatus({required this.lifecycle, this.safeDiagnostic});

  const NodeStatus.running({String? safeDiagnostic})
      : this(lifecycle: NodeLifecycle.running, safeDiagnostic: safeDiagnostic);

  final NodeLifecycle lifecycle;
  final String? safeDiagnostic;

  @override
  bool operator ==(Object other) =>
      other is NodeStatus &&
      lifecycle == other.lifecycle &&
      safeDiagnostic == other.safeDiagnostic;

  @override
  int get hashCode => Object.hash(lifecycle, safeDiagnostic);
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
}

final class _DefaultIpfsNodePlatform extends IpfsNodePlatform {
  Never _unimplemented(String operation) => throw UnimplementedError(
      'IpfsNodePlatform.$operation() has not been implemented.');

  @override
  Future<CapabilitySet> capabilities() async => _unimplemented('capabilities');

  @override
  Future<void> start(NodeConfig config) async => _unimplemented('start');

  @override
  Future<NodeStatus> status() async => _unimplemented('status');

  @override
  Future<void> stop() async => _unimplemented('stop');
}
