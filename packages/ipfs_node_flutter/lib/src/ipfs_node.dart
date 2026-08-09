import 'capability.dart';
import 'ipfs_node_backend.dart';
import 'ipfs_node_exception.dart';
import 'node_config.dart';
import 'node_status.dart';

final class IpfsNode {
  IpfsNode() : _backend = _UnavailableIpfsNodeBackend();

  IpfsNode.forTesting({
    required Future<void> Function(NodeConfig config) onStart,
    required Future<void> Function() onStop,
    required Future<NodeStatus> Function() onStatus,
    required Future<CapabilitySet> Function() onCapabilities,
  }) : _backend = _CallbackIpfsNodeBackend(
          onStart: onStart,
          onStop: onStop,
          onStatus: onStatus,
          onCapabilities: onCapabilities,
        );

  final IpfsNodeBackend _backend;
  CapabilitySet _capabilities = const CapabilitySet.empty();

  Future<void> start(NodeConfig config) async {
    await _backend.start(config);
    await capabilities();
  }

  Future<void> stop() => _backend.stop();

  Future<NodeStatus> status() => _backend.status();

  Future<CapabilitySet> capabilities() async {
    _capabilities = await _backend.capabilities();
    return _capabilities;
  }

  void require(Capability capability) {
    if (!_capabilities.contains(capability)) {
      throw UnsupportedCapabilityException(capability);
    }
  }
}

final class _CallbackIpfsNodeBackend implements IpfsNodeBackend {
  _CallbackIpfsNodeBackend({
    required this.onStart,
    required this.onStop,
    required this.onStatus,
    required this.onCapabilities,
  });

  final Future<void> Function(NodeConfig config) onStart;
  final Future<void> Function() onStop;
  final Future<NodeStatus> Function() onStatus;
  final Future<CapabilitySet> Function() onCapabilities;

  @override
  Future<CapabilitySet> capabilities() => onCapabilities();

  @override
  Future<void> start(NodeConfig config) => onStart(config);

  @override
  Future<NodeStatus> status() => onStatus();

  @override
  Future<void> stop() => onStop();
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
