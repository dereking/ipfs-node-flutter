import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';
import 'package:web/web.dart' as web;

import 'web_node_bridge.dart';

const _adapterAssets = [
  'assets/packages/ipfs_node_flutter_web/web/helia_adapter.js',
  'assets/web/helia_adapter.js',
  'packages/ipfs_node_flutter_web/web/helia_adapter.js',
];

@JS('IpfsNodeFlutterHelia')
external JSObject? get _registeredAdapter;

Future<void>? _adapterFuture;

WebNodeBridge createWebNodeBridge() => _JavascriptHeliaBridge();

@JS('IpfsNodeFlutterHelia.create')
external _HeliaNode _createHeliaNode();

extension type _HeliaNode._(JSObject _) implements JSObject {}

@JS('IpfsNodeFlutterHelia.start')
external void _startHeliaNode(
  _HeliaNode node,
  JSArray<JSString> peers,
  JSFunction resolve,
  JSFunction reject,
);
@JS('IpfsNodeFlutterHelia.stop')
external void _stopHeliaNode(
    _HeliaNode node, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.capabilities')
external void _heliaCapabilities(
    _HeliaNode node, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.addBytes')
external void _addHeliaBytes(
    _HeliaNode node, JSUint8Array bytes, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.getBytes')
external void _getHeliaBytes(
    _HeliaNode node, JSString cid, JSFunction resolve, JSFunction reject);

final class _JavascriptHeliaBridge implements WebNodeBridge {
  _HeliaNode? _node;
  CapabilitySet _capabilities = const CapabilitySet.empty();

  @override
  CapabilitySet get capabilities => _capabilities;

  @override
  Future<void> start({required List<String> bootstrapPeers}) async {
    if (_node != null) return;
    await (_adapterFuture ??= _loadAdapter());
    final node = _createHeliaNode();
    try {
      await _callback((resolve, reject) => _startHeliaNode(
          node,
          bootstrapPeers.map((peer) => peer.toJS).toList().toJS,
          resolve,
          reject));
      final names = await _callback<JSArray<JSString>>(
          (resolve, reject) => _heliaCapabilities(node, resolve, reject));
      _capabilities = _decodeCapabilities(names);
      _node = node;
    } catch (_) {
      await _callback(
          (resolve, reject) => _stopHeliaNode(node, resolve, reject));
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final node = _node;
    if (node == null) return;
    try {
      await _callback(
          (resolve, reject) => _stopHeliaNode(node, resolve, reject));
    } finally {
      _node = null;
      _capabilities = const CapabilitySet.empty();
    }
  }

  @override
  Future<String> addBytes(Uint8List bytes) async {
    final cid = await _callback<JSString>((resolve, reject) =>
        _addHeliaBytes(_requireNode(), bytes.toJS, resolve, reject));
    return cid.toDart;
  }

  @override
  Future<Uint8List> getBytes(String cid) async {
    final bytes = await _callback<JSUint8Array>((resolve, reject) =>
        _getHeliaBytes(_requireNode(), cid.toJS, resolve, reject));
    return bytes.toDart;
  }

  _HeliaNode _requireNode() =>
      _node ?? (throw StateError('The browser IPFS node has not started.'));
}

Future<T> _callback<T extends JSAny?>(
  void Function(JSFunction resolve, JSFunction reject) invoke,
) {
  final completer = Completer<T>();
  void resolve(JSAny? value) => completer.complete(value as T);
  void reject(JSAny? error) => completer.completeError(
      StateError(error is JSString ? error.toDart : 'Helia operation failed.'));
  invoke(resolve.toJS, reject.toJS);
  return completer.future;
}

Future<void> _loadAdapter() async {
  final installed = _registeredAdapter;
  if (installed != null) return;

  Object? lastError;
  for (final asset in _adapterAssets) {
    try {
      await _loadScript(asset);
      final adapter = _registeredAdapter;
      if (adapter != null) return;
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
