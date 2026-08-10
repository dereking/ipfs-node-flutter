import 'package:flutter/services.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

import 'web_node_bridge.dart';
import 'web_node_bridge_stub.dart'
    if (dart.library.js_interop) 'web_node_bridge_browser.dart';

/// Browser [IpfsNodePlatform] implementation backed by Helia and js-libp2p.
final class IpfsNodeFlutterWeb extends IpfsNodePlatform {
  IpfsNodeFlutterWeb({WebNodeBridge? bridge}) : _bridge = bridge;

  WebNodeBridge? _bridge;
  NodeLifecycle _lifecycle = NodeLifecycle.stopped;

  /// Installs this backend as the default platform implementation.
  ///
  /// The optional [registrar] is supplied by the Flutter web plugin
  /// registrant and is unused: this backend registers directly through the
  /// platform interface instead of a method channel.
  static void registerWith([Object? registrar]) {
    IpfsNodePlatform.instance = IpfsNodeFlutterWeb();
  }

  @override
  IpfsNodePlatform create() => IpfsNodeFlutterWeb();

  @override
  Future<void> start(NodeConfig config) async {
    if (config is PrivateNodeConfig) {
      throw UnsupportedCapabilityException(Capability.privateSwarmKey);
    }
    _lifecycle = NodeLifecycle.starting;
    try {
      await _runtimeBridge.start(
        bootstrapPeers: (config as PublicNodeConfig).bootstrapPeers,
        adapterAssetUrl: await _resolveAdapterAsset(),
      );
      _lifecycle = NodeLifecycle.running;
    } catch (_) {
      _lifecycle = NodeLifecycle.failed;
      rethrow;
    }
  }

  /// Resolves the bundled Helia adapter asset path from the Flutter asset
  /// manifest so runtime injection uses the exact served URL instead of
  /// guessing. Returns null when the asset is not bundled (fall back to
  /// conventional candidate paths).
  Future<String?> _resolveAdapterAsset() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final asset in manifest.listAssets()) {
        if (asset.startsWith(
            'packages/ipfs_node_flutter_web/web/helia_adapter.js')) {
          return 'assets/$asset';
        }
      }
    } catch (_) {
      // Asset manifest unavailable; fall back to candidate paths.
    }
    return null;
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
  Future<NodeStatus> status() async => NodeStatus(
        lifecycle: _lifecycle,
        // A started browser node always runs a client-mode DHT over the Amino
        // bootstrap peers; the native backend reports live routing-table size.
        dhtReady: _lifecycle == NodeLifecycle.running,
      );

  @override
  Future<CapabilitySet> capabilities() async =>
      _bridge?.capabilities ?? const CapabilitySet.empty();

  /// Stores opaque bytes as a UnixFS file in the local Helia blockstore.
  @override
  Future<IpfsAddResult> addBytes(Uint8List bytes) async {
    final cid = await _runtimeBridge.addBytes(bytes);
    return IpfsAddResult(cid: cid, bytes: bytes.length);
  }

  /// Retrieves opaque bytes for a locally stored CID or one provided by a
  /// connected libp2p peer.
  Future<List<int>> getBytes(String cid) => _runtimeBridge.getBytes(cid);

  @override
  Future<Uint8List> getBlock(
    String cid, {
    Duration timeout = const Duration(seconds: 180),
  }) =>
      _runtimeBridge.getBytes(cid).timeout(timeout);

  @override
  Future<void> pin(String cid) => _runtimeBridge.pin(cid);

  @override
  Future<void> unpin(String cid) => _runtimeBridge.unpin(cid);

  @override
  Future<List<IpfsPinInfo>> listPins() => _runtimeBridge.listPins();

  @override
  Future<List<IpfsPeerInfo>> swarmPeers() => _runtimeBridge.swarmPeers();

  @override
  Future<List<String>> bootstrapList() => _runtimeBridge.bootstrapList();

  @override
  Future<void> bootstrapAdd(String multiaddr) =>
      _runtimeBridge.bootstrapAdd(multiaddr);

  @override
  Future<void> bootstrapRemove(String multiaddr) =>
      _runtimeBridge.bootstrapRemove(multiaddr);

  @override
  Future<List<IpfsPeerInfo>> findProviders(
    String cid, {
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _runtimeBridge.findProviders(cid, timeout: timeout);

  @override
  Future<IpfsPeerInfo> findPeer(
    String peerId, {
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _runtimeBridge.findPeer(peerId, timeout: timeout);

  @override
  Future<IpfsBitswapStats> bitswapStats() => _runtimeBridge.bitswapStats();

  @override
  Future<String> publishName(
    String cid, {
    Duration timeout = const Duration(seconds: 60),
  }) =>
      _runtimeBridge.publishName(cid, timeout: timeout);

  @override
  Future<String> resolveName(
    String name, {
    Duration timeout = const Duration(seconds: 60),
  }) =>
      _runtimeBridge.resolveName(name, timeout: timeout);

  @override
  Future<List<IpfsKeyInfo>> listKeys() => _runtimeBridge.listKeys();

  WebNodeBridge get _runtimeBridge => _bridge ??= createWebNodeBridge();
}
