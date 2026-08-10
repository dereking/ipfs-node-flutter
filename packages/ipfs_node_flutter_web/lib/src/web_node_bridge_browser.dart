import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';
import 'package:web/web.dart' as web;

import 'web_node_bridge.dart';

const _adapterAssets = [
  // Flutter-bundled package asset (declared in this package's pubspec).
  'assets/packages/ipfs_node_flutter_web/web/helia_adapter.js',
  // Optional override placed in the host app's own web/ directory.
  'web/helia_adapter.js',
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
@JS('IpfsNodeFlutterHelia.pin')
external void _pinHeliaCid(
    _HeliaNode node, JSString cid, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.unpin')
external void _unpinHeliaCid(
    _HeliaNode node, JSString cid, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.listPins')
external void _listHeliaPins(
    _HeliaNode node, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.swarmPeers')
external void _heliaSwarmPeers(
    _HeliaNode node, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.bootstrapList')
external void _heliaBootstrapList(
    _HeliaNode node, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.bootstrapAdd')
external void _heliaBootstrapAdd(
    _HeliaNode node, JSString multiaddr, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.bootstrapRemove')
external void _heliaBootstrapRemove(
    _HeliaNode node, JSString multiaddr, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.findProviders')
external void _heliaFindProviders(_HeliaNode node, JSString cid,
    JSNumber timeoutMillis, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.findPeer')
external void _heliaFindPeer(_HeliaNode node, JSString peerId,
    JSNumber timeoutMillis, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.publishName')
external void _heliaPublishName(_HeliaNode node, JSString cid,
    JSNumber timeoutMillis, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.resolveName')
external void _heliaResolveName(_HeliaNode node, JSString name,
    JSNumber timeoutMillis, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.listKeys')
external void _heliaListKeys(
    _HeliaNode node, JSFunction resolve, JSFunction reject);
@JS('IpfsNodeFlutterHelia.bitswapStats')
external void _heliaBitswapStats(
    _HeliaNode node, JSFunction resolve, JSFunction reject);

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
    } catch (error) {
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

  @override
  Future<void> pin(String cid) async {
    await _callback<JSAny?>((resolve, reject) =>
        _pinHeliaCid(_requireNode(), cid.toJS, resolve, reject));
  }

  @override
  Future<void> unpin(String cid) async {
    await _callback<JSAny?>((resolve, reject) =>
        _unpinHeliaCid(_requireNode(), cid.toJS, resolve, reject));
  }

  @override
  Future<List<IpfsPinInfo>> listPins() async {
    final pins = await _callback<JSArray<JSObject>>(
        (resolve, reject) => _listHeliaPins(_requireNode(), resolve, reject));
    return pins.toDart.map(_decodePin).toList(growable: false);
  }

  @override
  Future<List<IpfsPeerInfo>> swarmPeers() async {
    final peers = await _callback<JSArray<JSObject>>(
        (resolve, reject) => _heliaSwarmPeers(_requireNode(), resolve, reject));
    return peers.toDart.map(_decodePeer).toList(growable: false);
  }

  @override
  Future<List<String>> bootstrapList() async {
    final peers = await _callback<JSArray<JSString>>((resolve, reject) =>
        _heliaBootstrapList(_requireNode(), resolve, reject));
    return peers.toDart.map((peer) => peer.toDart).toList(growable: false);
  }

  @override
  Future<void> bootstrapAdd(String multiaddr) async {
    await _callback<JSAny?>((resolve, reject) =>
        _heliaBootstrapAdd(_requireNode(), multiaddr.toJS, resolve, reject));
  }

  @override
  Future<void> bootstrapRemove(String multiaddr) async {
    await _callback<JSAny?>((resolve, reject) =>
        _heliaBootstrapRemove(_requireNode(), multiaddr.toJS, resolve, reject));
  }

  @override
  Future<List<IpfsPeerInfo>> findProviders(
    String cid, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final peers = await _callback<JSArray<JSObject>>((resolve, reject) =>
        _heliaFindProviders(_requireNode(), cid.toJS,
            timeout.inMilliseconds.toJS, resolve, reject));
    return peers.toDart.map(_decodePeer).toList(growable: false);
  }

  @override
  Future<IpfsPeerInfo> findPeer(
    String peerId, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final peer = await _callback<JSObject?>((resolve, reject) => _heliaFindPeer(
        _requireNode(),
        peerId.toJS,
        timeout.inMilliseconds.toJS,
        resolve,
        reject));
    return _decodePeer(peer);
  }

  @override
  Future<String> publishName(
    String cid, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final name = await _callback<JSString>((resolve, reject) =>
        _heliaPublishName(_requireNode(), cid.toJS, timeout.inMilliseconds.toJS,
            resolve, reject));
    return name.toDart;
  }

  @override
  Future<String> resolveName(
    String name, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final value = await _callback<JSString>((resolve, reject) =>
        _heliaResolveName(_requireNode(), name.toJS,
            timeout.inMilliseconds.toJS, resolve, reject));
    return value.toDart;
  }

  @override
  Future<List<IpfsKeyInfo>> listKeys() async {
    final keys = await _callback<JSArray<JSObject>>(
        (resolve, reject) => _heliaListKeys(_requireNode(), resolve, reject));
    return keys.toDart.map((raw) {
      final map = raw.dartify() as Map<dynamic, dynamic>;
      final name = map['name'];
      final peerId = map['peerId'];
      if (name is! String || peerId is! String) {
        throw StateError('Helia returned an invalid key entry.');
      }
      return IpfsKeyInfo(name: name, peerId: peerId);
    }).toList(growable: false);
  }

  @override
  Future<IpfsBitswapStats> bitswapStats() async {
    final stats = await _callback<JSObject?>((resolve, reject) =>
        _heliaBitswapStats(_requireNode(), resolve, reject));
    final map = stats?.dartify() as Map<dynamic, dynamic>? ?? const {};
    final blocksReceived = map['blocksReceived'];
    final dataReceived = map['dataReceived'];
    final wantlist = map['wantlist'];
    final messagesSent = map['messagesSent'];
    final messagesReceived = map['messagesReceived'];
    if (blocksReceived is! int ||
        dataReceived is! int ||
        wantlist is! int ||
        messagesSent is! int ||
        messagesReceived is! int) {
      throw StateError('Helia returned invalid bitswap stats.');
    }
    return IpfsBitswapStats(
      blocksReceived: blocksReceived,
      dataReceived: dataReceived,
      wantlist: wantlist,
      messagesSent: messagesSent,
      messagesReceived: messagesReceived,
    );
  }

  IpfsPinInfo _decodePin(JSObject raw) {
    final map = raw.dartify() as Map<dynamic, dynamic>;
    final cid = map['cid'];
    final type = map['type'];
    if (cid is! String || type is! String) {
      throw StateError('Helia returned an invalid pin entry.');
    }
    return IpfsPinInfo(
      cid: cid,
      type: type == 'recursive' ? IpfsPinType.recursive : IpfsPinType.direct,
    );
  }

  IpfsPeerInfo _decodePeer(JSObject? raw) {
    if (raw == null) return const IpfsPeerInfo(id: '');
    final map = raw.dartify() as Map<dynamic, dynamic>;
    final id = map['id'];
    final addrs = map['addrs'];
    if (id is! String || addrs is! List) {
      throw StateError('Helia returned an invalid peer entry.');
    }
    return IpfsPeerInfo(id: id, addrs: addrs.cast<String>());
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
  final timer = Timer(const Duration(seconds: 10), () {
    if (!loaded.isCompleted) {
      loaded.completeError(StateError('Timed out loading $asset.'));
    }
  });
  script.addEventListener(
      'load',
      ((web.Event _) {
        timer.cancel();
        loaded.complete();
      }).toJS);
  script.addEventListener(
    'error',
    ((web.Event _) {
      timer.cancel();
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
