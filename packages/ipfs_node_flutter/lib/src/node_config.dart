sealed class NodeConfig {
  const NodeConfig._();

  factory NodeConfig.publicNetwork({List<String> bootstrapPeers}) =
      PublicNodeConfig;

  factory NodeConfig.privateNetwork({
    required String swarmKey,
    List<String> bootstrapPeers,
    List<String> relayPeers,
    List<String> allowedPeerIds,
  }) = PrivateNodeConfig;
}

final class PublicNodeConfig extends NodeConfig {
  PublicNodeConfig({List<String> bootstrapPeers = const []})
      : bootstrapPeers = List.unmodifiable(bootstrapPeers),
        super._();

  final List<String> bootstrapPeers;
}

final class PrivateNodeConfig extends NodeConfig {
  PrivateNodeConfig({
    required this.swarmKey,
    List<String> bootstrapPeers = const [],
    List<String> relayPeers = const [],
    List<String> allowedPeerIds = const [],
  })  : bootstrapPeers = List.unmodifiable(bootstrapPeers),
        relayPeers = List.unmodifiable(relayPeers),
        allowedPeerIds = List.unmodifiable(allowedPeerIds),
        super._() {
    if (swarmKey.isEmpty) {
      throw ArgumentError.value(swarmKey, 'swarmKey', 'must not be empty');
    }
  }

  final String swarmKey;
  final List<String> bootstrapPeers;
  final List<String> relayPeers;
  final List<String> allowedPeerIds;
}
