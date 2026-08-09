import 'package:flutter/foundation.dart';

import 'capability.dart';
import 'ipfs_node_backend.dart';
import 'ipfs_node_exception.dart';
import 'node_config.dart';
import 'node_status.dart';

final class IpfsNode {
  @visibleForTesting
  IpfsNode.forTesting(this._backend);

  final IpfsNodeBackend _backend;
  Set<Capability> _capabilities = const {};

  Future<void> start(NodeConfig config) async {
    await _backend.start(config);
    _capabilities = Set.unmodifiable(await _backend.capabilities());
  }

  Future<void> stop() => _backend.stop();

  Future<NodeStatus> status() => _backend.status();

  Future<Set<Capability>> capabilities() async {
    _capabilities = Set.unmodifiable(await _backend.capabilities());
    return _capabilities;
  }

  void require(Capability capability) {
    if (!_capabilities.contains(capability)) {
      throw UnsupportedCapabilityException(capability);
    }
  }
}
