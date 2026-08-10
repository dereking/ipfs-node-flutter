import 'dart:math';
import 'dart:typed_data';

import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

enum ExampleNetworkMode { public, private }

final class ExampleNodeConfiguration {
  const ExampleNodeConfiguration.public({
    this.bootstrapPeers = const [],
  })  : mode = ExampleNetworkMode.public,
        swarmKeyHex = null,
        relayPeers = const [],
        allowedPeerIds = const {};

  const ExampleNodeConfiguration.private({
    required this.swarmKeyHex,
    this.bootstrapPeers = const [],
    this.relayPeers = const [],
    this.allowedPeerIds = const {},
  }) : mode = ExampleNetworkMode.private;

  final ExampleNetworkMode mode;
  final String? swarmKeyHex;
  final List<String> bootstrapPeers;
  final List<String> relayPeers;
  final Set<String> allowedPeerIds;

  String repositoryPath(String applicationSupportPath) {
    final base = applicationSupportPath.endsWith('/')
        ? applicationSupportPath.substring(0, applicationSupportPath.length - 1)
        : applicationSupportPath;
    if (mode == ExampleNetworkMode.public) {
      return '$base/ipfs-node/public';
    }
    return '$base/ipfs-node/private/$swarmKeyFingerprint';
  }

  String get swarmKeyFingerprint {
    final key = parseSwarmKey(swarmKeyHex ?? '');
    var hash = 0xcbf29ce484222325;
    for (final byte in key) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String get maskedSwarmKey => mode == ExampleNetworkMode.private
      ? '•••••••••••••••• ($swarmKeyFingerprint)'
      : '不适用';

  NodeConfig build(String applicationSupportPath) {
    final path = repositoryPath(applicationSupportPath);
    if (mode == ExampleNetworkMode.public) {
      return NodeConfig.public(
        repositoryPath: path,
        bootstrapPeers: bootstrapPeers,
      );
    }
    return NodeConfig.private(
      repositoryPath: path,
      swarmKey: parseSwarmKey(swarmKeyHex ?? ''),
      bootstrapPeers: bootstrapPeers,
      relayPeers: relayPeers,
      allowedPeerIds: allowedPeerIds,
    );
  }

  static Uint8List parseSwarmKey(String value) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      throw const FormatException('Swarm key 必须是 64 位十六进制文本');
    }
    return Uint8List.fromList([
      for (var index = 0; index < value.length; index += 2)
        int.parse(value.substring(index, index + 2), radix: 16),
    ]);
  }

  static String generateSwarmKeyHex(Random random) => List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
}
