import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

import 'ipfs_node_exception.dart';

final class IpfsNode {
  IpfsNode({IpfsNodePlatform? platform})
      : _platform = platform ?? IpfsNodePlatform.instance;

  final IpfsNodePlatform _platform;
  CapabilitySet _capabilities = const CapabilitySet.empty();

  Future<void> start(NodeConfig config) async {
    await _platform.start(config);
    await capabilities();
  }

  Future<void> stop() => _platform.stop();

  Future<NodeStatus> status() => _platform.status();

  Future<CapabilitySet> capabilities() async {
    _capabilities = await _platform.capabilities();
    return _capabilities;
  }

  void require(Capability capability) {
    if (!_capabilities.contains(capability)) {
      throw UnsupportedCapabilityException(capability);
    }
  }
}
