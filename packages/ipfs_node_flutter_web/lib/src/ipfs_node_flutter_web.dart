import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';
import 'dart:typed_data';

import 'web_node_bridge.dart';
import 'web_node_bridge_stub.dart'
    if (dart.library.js_interop) 'web_node_bridge_browser.dart';

/// Browser [IpfsNodePlatform] implementation backed by Helia and js-libp2p.
final class IpfsNodeFlutterWeb extends IpfsNodePlatform {
  IpfsNodeFlutterWeb({WebNodeBridge? bridge}) : _bridge = bridge;

  WebNodeBridge? _bridge;
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
        'Private swarm-key networks are not supported by the browser backend.',
      );
    }
    _lifecycle = NodeLifecycle.starting;
    try {
      await _runtimeBridge.start(
        bootstrapPeers: (config as PublicNodeConfig).bootstrapPeers,
      );
      _lifecycle = NodeLifecycle.running;
    } catch (_) {
      _lifecycle = NodeLifecycle.failed;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (_lifecycle == NodeLifecycle.stopped) return;
    _lifecycle = NodeLifecycle.stopping;
    try {
      await _runtimeBridge.stop();
    } finally {
      _lifecycle = NodeLifecycle.stopped;
    }
  }

  @override
  Future<NodeStatus> status() async => NodeStatus(lifecycle: _lifecycle);

  @override
  Future<CapabilitySet> capabilities() async =>
      _bridge?.capabilities ?? const CapabilitySet.empty();

  /// Stores opaque bytes as a UnixFS file in the local Helia blockstore.
  Future<String> addBytes(List<int> bytes) =>
      _runtimeBridge.addBytes(Uint8List.fromList(bytes));

  /// Retrieves opaque bytes for a locally or network-resolvable UnixFS CID.
  Future<List<int>> getBytes(String cid) => _runtimeBridge.getBytes(cid);

  WebNodeBridge get _runtimeBridge => _bridge ??= createWebNodeBridge();
}
