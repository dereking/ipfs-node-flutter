import 'capability.dart';
import 'ipfs_node_backend.dart';
import 'ipfs_node_exception.dart';
import 'node_config.dart';
import 'node_status.dart';

final class IpfsNode {
  IpfsNode({IpfsNodeBackend? backend})
      : _backend = backend ?? _UnavailableIpfsNodeBackend();

  final IpfsNodeBackend _backend;
  CapabilitySet _capabilities = const CapabilitySet.empty();

  Future<void> start(NodeConfig config) async {
    await _backend.start(config);
    _capabilities = await _backend.capabilities();
  }

  Future<void> stop() => _backend.stop();

  Future<NodeStatus> status() => _backend.status();

  CapabilitySet capabilities() => _capabilities;

  void require(Capability capability) {
    if (!_capabilities.contains(capability)) {
      throw UnsupportedCapabilityException(capability);
    }
  }
}

final class _UnavailableIpfsNodeBackend implements IpfsNodeBackend {
  Never _unavailable() => throw UnsupportedError(
        'No IPFS node backend is registered for this platform.',
      );

  @override
  Future<CapabilitySet> capabilities() async => _unavailable();

  @override
  Future<void> start(NodeConfig config) async => _unavailable();

  @override
  Future<NodeStatus> status() async => _unavailable();

  @override
  Future<void> stop() async => _unavailable();
}
