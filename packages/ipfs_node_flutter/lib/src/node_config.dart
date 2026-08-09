sealed class NodeConfig {
  const NodeConfig._();

  factory NodeConfig.public({List<String> bootstrapPeers = const []}) =>
      PublicNodeConfig(bootstrapPeers: bootstrapPeers);

  factory NodeConfig.private({
    required List<int> swarmKey,
    List<String> bootstrapPeers = const [],
    List<String> relayPeers = const [],
    Set<String> allowedPeerIds = const {},
  }) {
    if (swarmKey.isEmpty) {
      throw ArgumentError.value(swarmKey, 'swarmKey', 'must not be empty');
    }
    return PrivateNodeConfig(
      swarmKey: swarmKey,
      bootstrapPeers: bootstrapPeers,
      relayPeers: relayPeers,
      allowedPeerIds: allowedPeerIds,
    );
  }
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
