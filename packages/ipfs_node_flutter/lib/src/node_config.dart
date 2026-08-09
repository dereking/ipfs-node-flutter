sealed class NodeConfig {
  const NodeConfig._();

  const factory NodeConfig.public({List<String> bootstrapPeers}) =
      PublicNodeConfig;

  const factory NodeConfig.private({
    required List<int> swarmKey,
    List<String> bootstrapPeers,
    List<String> relayPeers,
    Set<String> allowedPeerIds,
  }) = PrivateNodeConfig;
}

final class PublicNodeConfig extends NodeConfig {
  const PublicNodeConfig({List<String> bootstrapPeers = const []})
      : _bootstrapPeers = bootstrapPeers,
        super._();

  final List<String> _bootstrapPeers;

  List<String> get bootstrapPeers => List.unmodifiable(_bootstrapPeers);

  @override
  bool operator ==(Object other) =>
      other is PublicNodeConfig &&
      _listsEqual(_bootstrapPeers, other._bootstrapPeers);

  @override
  int get hashCode => Object.hashAll(_bootstrapPeers);
}

final class PrivateNodeConfig extends NodeConfig {
  const PrivateNodeConfig({
    required List<int> swarmKey,
    List<String> bootstrapPeers = const [],
    List<String> relayPeers = const [],
    Set<String> allowedPeerIds = const {},
  })  : _swarmKey = swarmKey,
        _bootstrapPeers = bootstrapPeers,
        _relayPeers = relayPeers,
        _allowedPeerIds = allowedPeerIds,
        super._();

  final List<int> _swarmKey;
  final List<String> _bootstrapPeers;
  final List<String> _relayPeers;
  final Set<String> _allowedPeerIds;

  List<int> get swarmKey => List.unmodifiable(_swarmKey);
  List<String> get bootstrapPeers => List.unmodifiable(_bootstrapPeers);
  List<String> get relayPeers => List.unmodifiable(_relayPeers);
  Set<String> get allowedPeerIds => Set.unmodifiable(_allowedPeerIds);

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
