import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';
import 'dart:typed_data';

final class IpfsNode {
  IpfsNode({IpfsNodePlatform? platform})
      : _platform = platform ?? IpfsNodePlatform.instance.create();

  final IpfsNodePlatform _platform;
  CapabilitySet _capabilities = const CapabilitySet.empty();

  Future<void> start(NodeConfig config) async {
    await _platform.start(config);
    await capabilities();
  }

  Future<void> stop() => _platform.stop();

  Future<void> dispose() => _platform.dispose();

  Future<NodeStatus> status() => _platform.status();

  Future<CapabilitySet> capabilities() async {
    _capabilities = await _platform.capabilities();
    return _capabilities;
  }

  /// Retrieves and verifies one raw IPFS block by CID.
  Future<Uint8List> getBlock(
    String cid, {
    Duration timeout = const Duration(seconds: 90),
  }) =>
      _platform.getBlock(cid, timeout: timeout);

  void require(Capability capability) {
    if (!_capabilities.contains(capability)) {
      throw UnsupportedCapabilityException(capability);
    }
  }
}
