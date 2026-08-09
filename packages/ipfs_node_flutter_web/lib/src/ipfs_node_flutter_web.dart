import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

/// Browser implementation reserved for the future Helia backend.
///
/// Until Helia is linked, it explicitly reports no IPFS capabilities instead
/// of proxying requests through an HTTP gateway or advertising unsupported
/// browser transports.
final class IpfsNodeFlutterWeb extends IpfsNodePlatform {
  static const _heliaRequired = 'Web IPFS support requires the Helia backend.';

  NodeLifecycle _lifecycle = NodeLifecycle.stopped;

  /// Installs this backend as the default platform implementation.
  static void registerWith() {
    IpfsNodePlatform.instance = IpfsNodeFlutterWeb();
  }

  @override
  IpfsNodePlatform create() => IpfsNodeFlutterWeb();

  @override
  Future<void> start(NodeConfig config) async {
    if (config is PrivateNodeConfig) {
      throw UnsupportedError(
        'Private swarm-key networks require the Helia web backend.',
      );
    }
    _lifecycle = NodeLifecycle.degraded;
  }

  @override
  Future<void> stop() async {
    _lifecycle = NodeLifecycle.stopped;
  }

  @override
  Future<NodeStatus> status() async => switch (_lifecycle) {
        NodeLifecycle.degraded => const NodeStatus(
            lifecycle: NodeLifecycle.degraded,
            safeDiagnostic: _heliaRequired,
          ),
        _ => NodeStatus(lifecycle: _lifecycle),
      };

  @override
  Future<CapabilitySet> capabilities() async => const CapabilitySet.empty();
}
