import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';
import 'package:web/web.dart' as web;

import 'web_node_bridge.dart';

const _adapterAssets = [
  'assets/packages/ipfs_node_flutter_web/web/helia_adapter.js',
  'assets/web/helia_adapter.js',
];

@JS('IpfsNodeFlutterHelia')
external JSObject? get _registeredAdapter;

Future<JSObject>? _adapterFuture;

WebNodeBridge createWebNodeBridge() => _JavascriptHeliaBridge();

final class _JavascriptHeliaBridge implements WebNodeBridge {
  JSObject? _node;
  CapabilitySet _capabilities = const CapabilitySet.empty();

  @override
  CapabilitySet get capabilities => _capabilities;

  @override
  Future<void> start({required List<String> bootstrapPeers}) async {
    if (_node != null) return;
    final api = await (_adapterFuture ??= _loadAdapter());
    final node =
        await api.callMethod<JSPromise<JSObject>>('create'.toJS).toDart;
    try {
      await node
          .callMethod<JSPromise<JSAny?>>(
            'start'.toJS,
            bootstrapPeers.map((peer) => peer.toJS).toList().toJS,
          )
          .toDart;
      final names = await node
          .callMethod<JSPromise<JSArray<JSString>>>('capabilities'.toJS)
          .toDart;
      _capabilities = _decodeCapabilities(names);
      _node = node;
    } catch (_) {
      await node.callMethod<JSPromise<JSAny?>>('stop'.toJS).toDart;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final node = _node;
    if (node == null) return;
    try {
      await node.callMethod<JSPromise<JSAny?>>('stop'.toJS).toDart;
    } finally {
      _node = null;
      _capabilities = const CapabilitySet.empty();
    }
  }

  @override
  Future<String> addBytes(Uint8List bytes) async {
    final cid = await _requireNode()
        .callMethod<JSPromise<JSString>>('addBytes'.toJS, bytes.toJS)
        .toDart;
    return cid.toDart;
  }

  @override
  Future<Uint8List> getBytes(String cid) async {
    final bytes = await _requireNode()
        .callMethod<JSPromise<JSUint8Array>>('getBytes'.toJS, cid.toJS)
        .toDart;
    return bytes.toDart;
  }

  JSObject _requireNode() =>
      _node ?? (throw StateError('The browser IPFS node has not started.'));
}

Future<JSObject> _loadAdapter() async {
  final installed = _registeredAdapter;
  if (installed != null) return installed;

  Object? lastError;
  for (final asset in _adapterAssets) {
    try {
      await _loadScript(asset);
      final adapter = _registeredAdapter;
      if (adapter != null) return adapter;
      lastError = StateError('The Helia web adapter did not register its API.');
    } catch (error) {
      lastError = error;
    }
  }
  throw StateError('Unable to load the Helia web adapter: $lastError');
}

Future<void> _loadScript(String asset) async {
  final script = web.HTMLScriptElement()
    ..async = true
    ..src = asset;
  final loaded = Completer<void>();
  script.addEventListener('load', ((web.Event _) => loaded.complete()).toJS);
  script.addEventListener(
    'error',
    ((web.Event _) {
      loaded.completeError(StateError('Unable to load $asset.'));
    }).toJS,
  );
  web.document.head!.append(script);
  await loaded.future;
}

CapabilitySet _decodeCapabilities(JSArray<JSString> names) {
  final capabilities = <Capability>{};
  for (final name in names.toDart) {
    for (final capability in Capability.values) {
      if (capability.name == name.toDart) capabilities.add(capability);
    }
  }
  return CapabilitySet(capabilities);
}
