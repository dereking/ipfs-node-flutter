import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

/// Base type for errors raised by the native node adapter.
sealed class NativeNodeException implements Exception {
  const NativeNodeException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The packaged native artifact could not be loaded or did not expose its ABI.
final class NativeNodeLoadException extends NativeNodeException {
  const NativeNodeLoadException(
      {required this.artifact, required String message})
      : super(message);

  final String artifact;
}

/// Base type for errors returned by a native node operation.
sealed class NativeNodeOperationException extends NativeNodeException {
  const NativeNodeOperationException({
    required this.operation,
    required String message,
  }) : super(message);

  final String operation;
}

final class NativeNodeInvalidHandleException
    extends NativeNodeOperationException {
  const NativeNodeInvalidHandleException({required super.operation})
      : super(message: 'Native node handle is invalid.');
}

final class NativeNodeInvalidConfigurationException
    extends NativeNodeOperationException {
  const NativeNodeInvalidConfigurationException({required super.operation})
      : super(message: 'Native node configuration is invalid.');
}

final class NativeNodeInvalidStateException
    extends NativeNodeOperationException {
  const NativeNodeInvalidStateException({required super.operation})
      : super(message: 'Native node lifecycle state is invalid.');
}

final class NativeNodeProtocolException extends NativeNodeOperationException {
  const NativeNodeProtocolException(
      {required super.operation, required super.message});
}

/// A native network request was valid but could not be completed.
final class NativeNodeRequestException extends NativeNodeOperationException {
  const NativeNodeRequestException(
      {required super.operation, required super.message});
}

/// Native [IpfsNodePlatform] implementation backed by the packaged Go ABI.
final class IpfsNodeFlutterNative extends IpfsNodePlatform {
  /// [libraryPath] is intended for application packaging and integration tests.
  /// Omit it to use the platform's conventional IPFS node artifact name.
  IpfsNodeFlutterNative({String? libraryPath}) : _libraryPath = libraryPath;

  final String? _libraryPath;
  _FfiNativeNodeAbi? _abi;
  bool _disposed = false;

  /// Installs a factory that gives every default [IpfsNode] its own handle.
  static void registerWith({String? libraryPath}) {
    IpfsNodePlatform.instance = IpfsNodeFlutterNative(libraryPath: libraryPath);
  }

  @override
  IpfsNodePlatform create() => IpfsNodeFlutterNative(libraryPath: _libraryPath);

  @override
  Future<void> start(NodeConfig config) async {
    final encoded = _encodeStartRequest(config);
    final code = await _inIsolate((abi) => abi.start(encoded));
    _throwForError('start', code);
  }

  @override
  Future<void> stop() async {
    final code = await _inIsolate((abi) => abi.stop());
    _throwForError('stop', code);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    final abi = _abi;
    _disposed = true;
    _abi = null;
    if (abi == null) return;
    await _runInIsolateWith(abi, (worker) => worker.dispose());
  }

  @override
  Future<NodeStatus> status() async {
    final encoded =
        _requiredResponse('status', await _inIsolate((abi) => abi.status()));
    final map = _decodeObject('status', encoded);
    final lifecycleName = map['lifecycle'];
    if (lifecycleName is! String) {
      throw const NativeNodeProtocolException(
        operation: 'status',
        message: 'Native node response did not contain lifecycle.',
      );
    }
    final lifecycle =
        NodeLifecycle.values.where((value) => value.name == lifecycleName);
    if (lifecycle.isEmpty) {
      throw const NativeNodeProtocolException(
        operation: 'status',
        message: 'Native node response contained an unknown lifecycle.',
      );
    }
    final safeDiagnostic = map['safeDiagnostic'];
    if (safeDiagnostic != null && safeDiagnostic is! String) {
      throw const NativeNodeProtocolException(
        operation: 'status',
        message: 'Native node response contained an invalid diagnostic.',
      );
    }
    final peerId = map['peerId'];
    if (peerId != null && peerId is! String) {
      throw const NativeNodeProtocolException(
        operation: 'status',
        message: 'Native node response contained an invalid peer ID.',
      );
    }
    return NodeStatus(
      lifecycle: lifecycle.single,
      safeDiagnostic: safeDiagnostic as String?,
      peerId: peerId as String?,
      listenAddrs: _decodeStringList('status', map, 'listenAddrs'),
      connectedPeers: _decodeStringList('status', map, 'connectedPeers'),
      bootstrapErrors: _decodeStringList('status', map, 'bootstrapErrors'),
      relayAddrs: _decodeStringList('status', map, 'relayAddrs'),
      relayReady: map['relayReady'] == true,
      routingTableSize: map['routingTableSize'] is int
          ? map['routingTableSize'] as int
          : 0,
      dhtReady: map['dhtReady'] == true,
    );
  }

  @override
  Future<CapabilitySet> capabilities() async {
    final encoded = _requiredResponse(
        'capabilities', await _inIsolate((abi) => abi.capabilities()));
    final decoded = _decodeJson('capabilities', encoded);
    if (decoded is! List || decoded.any((value) => value is! String)) {
      throw const NativeNodeProtocolException(
        operation: 'capabilities',
        message: 'Native node response was not a string array.',
      );
    }
    final result = <Capability>{};
    for (final name in decoded.cast<String>()) {
      for (final capability in Capability.values) {
        if (capability.name == name) result.add(capability);
      }
    }
    return CapabilitySet(result);
  }

  @override
  Future<Uint8List> getBlock(
    String cid, {
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final encoded = _requiredResponse(
      'getBlock',
      await _inIsolate((abi) => abi.getBlock(cid, timeout.inMilliseconds)),
    );
    final map = _decodeObject('getBlock', encoded);
    final error = map['error'];
    if (error is String && error.isNotEmpty) {
      throw NativeNodeRequestException(operation: 'getBlock', message: error);
    }
    final data = map['data'];
    if (data is! String) {
      throw const NativeNodeProtocolException(
        operation: 'getBlock',
        message: 'Native node response did not contain block data.',
      );
    }
    try {
      return base64Decode(data);
    } on FormatException {
      throw const NativeNodeProtocolException(
        operation: 'getBlock',
        message: 'Native node response contained invalid base64 block data.',
      );
    }
  }

  @override
  Future<IpfsAddResult> addBytes(Uint8List bytes) async {
    final encoded = _requiredResponse(
      'addBytes',
      await _inIsolate((abi) {
        final pointer = calloc<Uint8>(bytes.length);
        pointer.asTypedList(bytes.length).setAll(0, bytes);
        try {
          return abi.addBytes(pointer.cast<Void>(), bytes.length);
        } finally {
          calloc.free(pointer);
        }
      }),
    );
    final map = _decodeObject('addBytes', encoded);
    final error = map['error'];
    if (error is String && error.isNotEmpty) {
      throw NativeNodeRequestException(operation: 'addBytes', message: error);
    }
    final cid = map['cid'];
    if (cid is! String || cid.isEmpty) {
      throw const NativeNodeProtocolException(
        operation: 'addBytes',
        message: 'Native node response did not contain a content root CID.',
      );
    }
    final added = map['bytes'];
    if (added is! int) {
      throw const NativeNodeProtocolException(
        operation: 'addBytes',
        message: 'Native node response did not contain the byte count.',
      );
    }
    return IpfsAddResult(cid: cid, bytes: added);
  }

  @override
  Future<void> pin(String cid) async {
    _throwForStringError('pin',
        _requiredResponse('pin', await _inIsolate((abi) => abi.pin(cid))));
  }

  @override
  Future<void> unpin(String cid) async {
    _throwForStringError('unpin',
        _requiredResponse('unpin', await _inIsolate((abi) => abi.unpin(cid))));
  }

  @override
  Future<List<IpfsPinInfo>> listPins() async => _decodeListOf(
        'listPins',
        _requiredResponse(
            'listPins', await _inIsolate((abi) => abi.listPins())),
        _decodePin,
      );

  @override
  Future<List<IpfsPeerInfo>> swarmPeers() async => _decodeListOf(
        'swarmPeers',
        _requiredResponse(
            'swarmPeers', await _inIsolate((abi) => abi.swarmPeers())),
        _decodePeer,
      );

  @override
  Future<void> swarmConnect(String multiaddr) async {
    _throwForStringError(
      'swarmConnect',
      _requiredResponse('swarmConnect',
          await _inIsolate((abi) => abi.swarmConnect(multiaddr))),
    );
  }

  @override
  Future<void> swarmDisconnect(String peerId) async {
    _throwForStringError(
      'swarmDisconnect',
      _requiredResponse('swarmDisconnect',
          await _inIsolate((abi) => abi.swarmDisconnect(peerId))),
    );
  }

  @override
  Future<List<String>> bootstrapList() async {
    final encoded = _requiredResponse(
        'bootstrapList', await _inIsolate((abi) => abi.bootstrapList()));
    final decoded = _decodeJson('bootstrapList', encoded);
    if (decoded is List) return List.unmodifiable(decoded.cast<String>());
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is String && error.isNotEmpty) {
        throw NativeNodeRequestException(
            operation: 'bootstrapList', message: error);
      }
    }
    throw const NativeNodeProtocolException(
      operation: 'bootstrapList',
      message: 'Native node response was not a bootstrap list.',
    );
  }

  @override
  Future<void> bootstrapAdd(String multiaddr) async {
    _throwForStringError(
      'bootstrapAdd',
      _requiredResponse('bootstrapAdd',
          await _inIsolate((abi) => abi.bootstrapAdd(multiaddr))),
    );
  }

  @override
  Future<void> bootstrapRemove(String multiaddr) async {
    _throwForStringError(
      'bootstrapRemove',
      _requiredResponse('bootstrapRemove',
          await _inIsolate((abi) => abi.bootstrapRemove(multiaddr))),
    );
  }

  @override
  Future<IpfsBitswapStats> bitswapStats() async {
    final map = _decodeObjectOrThrow(
      'bitswapStats',
      _requiredResponse(
          'bitswapStats', await _inIsolate((abi) => abi.bitswapStats())),
    );
    final blocksSent = map['blocksSent'];
    final blocksReceived = map['blocksReceived'];
    final dataSent = map['dataSent'];
    final dataReceived = map['dataReceived'];
    final wantlist = map['wantlist'];
    final messagesSent = map['messagesSent'];
    final messagesReceived = map['messagesReceived'];
    if (blocksSent is! int ||
        blocksReceived is! int ||
        dataSent is! int ||
        dataReceived is! int ||
        wantlist is! List ||
        messagesSent is! int ||
        messagesReceived is! int) {
      throw const NativeNodeProtocolException(
        operation: 'bitswapStats',
        message: 'Native node response contained invalid bitswap stats.',
      );
    }
    return IpfsBitswapStats(
      blocksSent: blocksSent,
      blocksReceived: blocksReceived,
      dataSent: dataSent,
      dataReceived: dataReceived,
      wantlist: wantlist.length,
      messagesSent: messagesSent,
      messagesReceived: messagesReceived,
    );
  }

  @override
  Future<List<IpfsPeerInfo>> findProviders(
    String cid, {
    Duration timeout = const Duration(seconds: 30),
  }) async =>
      _decodeListOf(
        'findProviders',
        _requiredResponse(
          'findProviders',
          await _inIsolate(
              (abi) => abi.findProviders(cid, timeout.inMilliseconds)),
        ),
        _decodePeer,
      );

  @override
  Future<IpfsPeerInfo> findPeer(
    String peerId, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final map = _decodeObjectOrThrow(
      'findPeer',
      _requiredResponse(
        'findPeer',
        await _inIsolate((abi) => abi.findPeer(peerId, timeout.inMilliseconds)),
      ),
    );
    return _decodePeer(map);
  }

  @override
  Future<String> publishName(
    String cid, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final map = _decodeObjectOrThrow(
      'publishName',
      _requiredResponse(
        'publishName',
        await _inIsolate((abi) => abi.publishName(cid, timeout.inMilliseconds)),
      ),
    );
    final name = map['name'];
    if (name is! String || name.isEmpty) {
      throw const NativeNodeProtocolException(
        operation: 'publishName',
        message: 'Native node response did not contain a name.',
      );
    }
    return name;
  }

  @override
  Future<String> resolveName(
    String name, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final map = _decodeObjectOrThrow(
      'resolveName',
      _requiredResponse(
        'resolveName',
        await _inIsolate(
            (abi) => abi.resolveName(name, timeout.inMilliseconds)),
      ),
    );
    final path = map['path'];
    if (path is! String || path.isEmpty) {
      throw const NativeNodeProtocolException(
        operation: 'resolveName',
        message: 'Native node response did not contain a path.',
      );
    }
    return path;
  }

  @override
  Future<List<IpfsKeyInfo>> listKeys() async => _decodeListOf(
        'listKeys',
        _requiredResponse(
            'listKeys', await _inIsolate((abi) => abi.listKeys())),
        _decodeKey,
      );

  _FfiNativeNodeAbi get _backend {
    if (_disposed) {
      throw const NativeNodeInvalidHandleException(operation: 'node operation');
    }
    return _abi ??= _loadAbi(_libraryPath);
  }

  /// Runs a blocking FFI operation in a worker isolate so the UI isolate never
  /// stalls while the native node performs slow network work (bootstrap,
  /// Bitswap, DHT, IPNS).
  Future<T> _inIsolate<T>(T Function(_FfiNativeNodeAbi abi) invoke) async {
    return _runInIsolateWith(_backend, invoke);
  }

  Future<T> _runInIsolateWith<T>(
    _FfiNativeNodeAbi abi,
    T Function(_FfiNativeNodeAbi abi) invoke,
  ) async {
    final libraryPath = _libraryPath;
    final handle = abi.handle;
    return Isolate.run(
      () =>
          invoke(_FfiNativeNodeAbi(_openLibrary(libraryPath), handle: handle)),
    );
  }
}

String _encodeStartRequest(NodeConfig config) => switch (config) {
      PublicNodeConfig(:final bootstrapPeers) => jsonEncode({
          'network': 'public',
          'bootstrapPeers': bootstrapPeers,
          'useDefaultBootstrap': bootstrapPeers.isEmpty,
        }),
      PrivateNodeConfig(:final swarmKey) => jsonEncode({
          'network': 'private',
          'swarmKey': base64Encode(swarmKey),
        }),
    };

List<String> _decodeStringList(
  String operation,
  Map<String, dynamic> map,
  String key,
) {
  final value = map[key];
  if (value == null) return const [];
  if (value is! List || value.any((element) => element is! String)) {
    throw NativeNodeProtocolException(
      operation: operation,
      message: 'Native node response contained an invalid $key list.',
    );
  }
  return List.unmodifiable(value.cast<String>());
}

_FfiNativeNodeAbi _loadAbi(String? libraryPath) {
  final artifact = libraryPath ?? _defaultArtifactName();
  try {
    return _FfiNativeNodeAbi(_openLibrary(libraryPath));
  } catch (error) {
    throw NativeNodeLoadException(
      artifact: artifact,
      message: 'Unable to load native IPFS node artifact: $error',
    );
  }
}

DynamicLibrary _openLibrary(String? libraryPath) {
  if (libraryPath == null && Platform.isIOS) {
    return DynamicLibrary.process();
  }
  return DynamicLibrary.open(libraryPath ?? _defaultArtifactName());
}

String _defaultArtifactName() => switch (Platform.operatingSystem) {
      'windows' => 'ipfs_node_core.dll',
      'linux' || 'android' => 'libipfs_node_core.so',
      'ios' => 'iOS application process',
      'macos' => '@executable_path/../Frameworks/libipfs_node_core.dylib',
      _ => 'libipfs_node_core.dylib',
    };

String _requiredResponse(String operation, String? value) {
  if (value == null) {
    throw NativeNodeInvalidHandleException(operation: operation);
  }
  return value;
}

Map<String, dynamic> _decodeObject(String operation, String encoded) {
  final decoded = _decodeJson(operation, encoded);
  if (decoded is! Map<String, dynamic>) {
    throw NativeNodeProtocolException(
      operation: operation,
      message: 'Native node response was not an object.',
    );
  }
  return decoded;
}

dynamic _decodeJson(String operation, String encoded) {
  try {
    return jsonDecode(encoded);
  } on FormatException {
    throw NativeNodeProtocolException(
      operation: operation,
      message: 'Native node response was not valid JSON.',
    );
  }
}

void _throwForError(String operation, _NativeReturnCode code) {
  switch (code) {
    case _NativeReturnCode.ok:
      return;
    case _NativeReturnCode.invalidHandle:
      throw NativeNodeInvalidHandleException(operation: operation);
    case _NativeReturnCode.invalidConfiguration:
      throw NativeNodeInvalidConfigurationException(operation: operation);
    case _NativeReturnCode.invalidState:
      throw NativeNodeInvalidStateException(operation: operation);
    case _NativeReturnCode.unknown:
      throw NativeNodeProtocolException(
        operation: operation,
        message: 'Native node returned an unknown error code.',
      );
  }
}

void _throwForStringError(String operation, String encoded) {
  final map = _decodeObject(operation, encoded);
  final error = map['error'];
  if (error is String && error.isNotEmpty) {
    throw NativeNodeRequestException(operation: operation, message: error);
  }
}

IpfsPinInfo _decodePin(Map<dynamic, dynamic> map) {
  final cid = map['cid'];
  final type = map['type'];
  if (cid is! String || cid.isEmpty || type is! String) {
    throw const NativeNodeProtocolException(
      operation: 'listPins',
      message: 'Native node response contained an invalid pin entry.',
    );
  }
  final pinType = switch (type) {
    'direct' => IpfsPinType.direct,
    'recursive' => IpfsPinType.recursive,
    _ => throw const NativeNodeProtocolException(
        operation: 'listPins',
        message: 'Native node response contained an unknown pin type.',
      ),
  };
  final rawPinnedAt = map['pinnedAt'];
  return IpfsPinInfo(
    cid: cid,
    type: pinType,
    pinnedAt: rawPinnedAt is String ? DateTime.tryParse(rawPinnedAt) : null,
  );
}

IpfsPeerInfo _decodePeer(Map<dynamic, dynamic> map) {
  final id = map['id'];
  final rawAddrs = map['addrs'];
  if (id is! String || id.isEmpty || rawAddrs is! List) {
    throw const NativeNodeProtocolException(
      operation: 'peer',
      message: 'Native node response contained an invalid peer entry.',
    );
  }
  return IpfsPeerInfo(
      id: id, addrs: List.unmodifiable(rawAddrs.cast<String>()));
}

IpfsKeyInfo _decodeKey(Map<dynamic, dynamic> map) {
  final name = map['name'];
  final peerId = map['peerId'];
  if (name is! String || name.isEmpty || peerId is! String || peerId.isEmpty) {
    throw const NativeNodeProtocolException(
      operation: 'key',
      message: 'Native node response contained an invalid key entry.',
    );
  }
  return IpfsKeyInfo(name: name, peerId: peerId);
}

List<T> _decodeListOf<T>(
  String operation,
  String encoded,
  T Function(Map<dynamic, dynamic>) decode,
) {
  final decoded = _decodeJson(operation, encoded);
  if (decoded is List) {
    return decoded
        .map((value) => decode((value as Map).cast<dynamic, dynamic>()))
        .toList(growable: false);
  }
  if (decoded is Map<String, dynamic>) {
    final error = decoded['error'];
    if (error is String && error.isNotEmpty) {
      throw NativeNodeRequestException(operation: operation, message: error);
    }
  }
  throw NativeNodeProtocolException(
    operation: operation,
    message: 'Native node response was not a list.',
  );
}

Map<String, dynamic> _decodeObjectOrThrow(String operation, String encoded) {
  final decoded = _decodeJson(operation, encoded);
  if (decoded is Map<String, dynamic>) {
    final error = decoded['error'];
    if (error is String && error.isNotEmpty) {
      throw NativeNodeRequestException(operation: operation, message: error);
    }
    return decoded;
  }
  throw NativeNodeProtocolException(
    operation: operation,
    message: 'Native node response was not an object.',
  );
}

enum _NativeReturnCode {
  ok(0),
  invalidHandle(1),
  invalidConfiguration(2),
  invalidState(3),
  unknown(-1);

  const _NativeReturnCode(this.value);

  final int value;

  static _NativeReturnCode fromValue(int value) =>
      _NativeReturnCode.values.firstWhere(
        (code) => code.value == value,
        orElse: () => _NativeReturnCode.unknown,
      );
}

final class _FfiNativeNodeAbi {
  /// [handle] supplies an existing native node handle (used by worker isolates
  /// so blocking calls never stall the UI isolate); when omitted a new node
  /// is created.
  _FfiNativeNodeAbi(DynamicLibrary library, {int? handle})
      : _create = library
            .lookupFunction<_CreateNative, _CreateDart>('ipfs_node_create'),
        _start =
            library.lookupFunction<_StartNative, _StartDart>('ipfs_node_start'),
        _stop =
            library.lookupFunction<_StopNative, _StopDart>('ipfs_node_stop'),
        _status = library
            .lookupFunction<_StringNative, _StringDart>('ipfs_node_status'),
        _capabilities = library.lookupFunction<_StringNative, _StringDart>(
          'ipfs_node_capabilities',
        ),
        _getBlock = library.lookupFunction<_GetBlockNative, _GetBlockDart>(
          'ipfs_node_get_block',
        ),
        _addBytes = library.lookupFunction<_AddBytesNative, _AddBytesDart>(
          'ipfs_node_add_bytes',
        ),
        _pin = library.lookupFunction<_PinNative, _PinDart>('ipfs_node_pin'),
        _unpin =
            library.lookupFunction<_PinNative, _PinDart>('ipfs_node_unpin'),
        _listPins = library.lookupFunction<_StringNative, _StringDart>(
          'ipfs_node_list_pins',
        ),
        _swarmPeers = library.lookupFunction<_StringNative, _StringDart>(
          'ipfs_node_swarm_peers',
        ),
        _swarmConnect = library
            .lookupFunction<_PinNative, _PinDart>('ipfs_node_swarm_connect'),
        _swarmDisconnect = library.lookupFunction<_PinNative, _PinDart>(
          'ipfs_node_swarm_disconnect',
        ),
        _bootstrapList = library.lookupFunction<_StringNative, _StringDart>(
          'ipfs_node_bootstrap_list',
        ),
        _bootstrapAdd = library.lookupFunction<_PinNative, _PinDart>(
          'ipfs_node_bootstrap_add',
        ),
        _bootstrapRemove = library.lookupFunction<_PinNative, _PinDart>(
          'ipfs_node_bootstrap_remove',
        ),
        _bitswapStats = library.lookupFunction<_StringNative, _StringDart>(
          'ipfs_node_bitswap_stats',
        ),
        _findProviders = library.lookupFunction<_TimeoutNative, _TimeoutDart>(
          'ipfs_node_find_providers',
        ),
        _findPeer = library.lookupFunction<_TimeoutNative, _TimeoutDart>(
          'ipfs_node_find_peer',
        ),
        _publishName = library.lookupFunction<_TimeoutNative, _TimeoutDart>(
          'ipfs_node_publish_name',
        ),
        _resolveName = library.lookupFunction<_TimeoutNative, _TimeoutDart>(
          'ipfs_node_resolve_name',
        ),
        _listKeys = library.lookupFunction<_StringNative, _StringDart>(
          'ipfs_node_list_keys',
        ),
        _free =
            library.lookupFunction<_FreeNative, _FreeDart>('ipfs_node_free'),
        _freeString =
            library.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'ipfs_node_free_string',
        ) {
    _handle = handle ?? _create();
    if (_handle == 0) {
      throw StateError('Native node creation returned an invalid handle.');
    }
  }

  final _CreateDart _create;
  final _StartDart _start;
  final _StopDart _stop;
  final _StringDart _status;
  final _StringDart _capabilities;
  final _GetBlockDart _getBlock;
  final _AddBytesDart _addBytes;
  final _PinDart _pin;
  final _PinDart _unpin;
  final _StringDart _listPins;
  final _StringDart _swarmPeers;
  final _PinDart _swarmConnect;
  final _PinDart _swarmDisconnect;
  final _StringDart _bootstrapList;
  final _PinDart _bootstrapAdd;
  final _PinDart _bootstrapRemove;
  final _StringDart _bitswapStats;
  final _TimeoutDart _findProviders;
  final _TimeoutDart _findPeer;
  final _TimeoutDart _publishName;
  final _TimeoutDart _resolveName;
  final _StringDart _listKeys;
  final _FreeDart _free;
  final _FreeStringDart _freeString;
  late int _handle;

  int get handle => _handle;

  _NativeReturnCode start(String request) {
    final value = request.toNativeUtf8().cast<Char>();
    try {
      return _NativeReturnCode.fromValue(_start(_handle, value));
    } finally {
      calloc.free(value);
    }
  }

  _NativeReturnCode stop() => _NativeReturnCode.fromValue(_stop(_handle));

  String? status() => _readString(_status);

  String? capabilities() => _readString(_capabilities);

  String? getBlock(String cid, int timeoutMillis) {
    final value = cid.toNativeUtf8().cast<Char>();
    try {
      final response = _getBlock(_handle, value, timeoutMillis);
      if (response == nullptr) return null;
      try {
        return response.cast<Utf8>().toDartString();
      } finally {
        _freeString(response);
      }
    } finally {
      calloc.free(value);
    }
  }

  String? addBytes(Pointer<Void> data, int length) {
    final response = _addBytes(_handle, data, length);
    if (response == nullptr) return null;
    try {
      return response.cast<Utf8>().toDartString();
    } finally {
      _freeString(response);
    }
  }

  String? pin(String value) => _callString(_pin, value);

  String? unpin(String value) => _callString(_unpin, value);

  String? listPins() => _readString(_listPins);

  String? swarmPeers() => _readString(_swarmPeers);

  String? swarmConnect(String value) => _callString(_swarmConnect, value);

  String? swarmDisconnect(String value) => _callString(_swarmDisconnect, value);

  String? bootstrapList() => _readString(_bootstrapList);

  String? bootstrapAdd(String value) => _callString(_bootstrapAdd, value);

  String? bootstrapRemove(String value) => _callString(_bootstrapRemove, value);

  String? bitswapStats() => _readString(_bitswapStats);

  String? findProviders(String value, int timeoutMillis) =>
      _callStringWithTimeout(_findProviders, value, timeoutMillis);

  String? findPeer(String value, int timeoutMillis) =>
      _callStringWithTimeout(_findPeer, value, timeoutMillis);

  String? publishName(String value, int timeoutMillis) =>
      _callStringWithTimeout(_publishName, value, timeoutMillis);

  String? resolveName(String value, int timeoutMillis) =>
      _callStringWithTimeout(_resolveName, value, timeoutMillis);

  String? listKeys() => _readString(_listKeys);

  String? _callString(_PinDart function, String value) {
    final encoded = value.toNativeUtf8().cast<Char>();
    try {
      final response = function(_handle, encoded);
      if (response == nullptr) return null;
      try {
        return response.cast<Utf8>().toDartString();
      } finally {
        _freeString(response);
      }
    } finally {
      calloc.free(encoded);
    }
  }

  String? _callStringWithTimeout(
    _TimeoutDart function,
    String value,
    int timeoutMillis,
  ) {
    final encoded = value.toNativeUtf8().cast<Char>();
    try {
      final response = function(_handle, encoded, timeoutMillis);
      if (response == nullptr) return null;
      try {
        return response.cast<Utf8>().toDartString();
      } finally {
        _freeString(response);
      }
    } finally {
      calloc.free(encoded);
    }
  }

  String? _readString(_StringDart function) {
    final value = function(_handle);
    if (value == nullptr) return null;
    try {
      return value.cast<Utf8>().toDartString();
    } finally {
      _freeString(value);
    }
  }

  void dispose() {
    if (_handle == 0) return;
    _stop(_handle);
    _free(_handle);
    _handle = 0;
  }
}

typedef _CreateNative = UintPtr Function();
typedef _CreateDart = int Function();
typedef _StartNative = Int32 Function(UintPtr handle, Pointer<Char> request);
typedef _StartDart = int Function(int handle, Pointer<Char> request);
typedef _StopNative = Int32 Function(UintPtr handle);
typedef _StopDart = int Function(int handle);
typedef _StringNative = Pointer<Char> Function(UintPtr handle);
typedef _StringDart = Pointer<Char> Function(int handle);
typedef _GetBlockNative = Pointer<Char> Function(
  UintPtr handle,
  Pointer<Char> cid,
  Int32 timeoutMillis,
);
typedef _GetBlockDart = Pointer<Char> Function(
  int handle,
  Pointer<Char> cid,
  int timeoutMillis,
);
typedef _AddBytesNative = Pointer<Char> Function(
  UintPtr handle,
  Pointer<Void> data,
  Size length,
);
typedef _AddBytesDart = Pointer<Char> Function(
  int handle,
  Pointer<Void> data,
  int length,
);
typedef _PinNative = Pointer<Char> Function(
  UintPtr handle,
  Pointer<Char> value,
);
typedef _PinDart = Pointer<Char> Function(int handle, Pointer<Char> value);
typedef _TimeoutNative = Pointer<Char> Function(
  UintPtr handle,
  Pointer<Char> value,
  Int32 timeoutMillis,
);
typedef _TimeoutDart = Pointer<Char> Function(
  int handle,
  Pointer<Char> value,
  int timeoutMillis,
);
typedef _FreeNative = Void Function(UintPtr handle);
typedef _FreeDart = void Function(int handle);
typedef _FreeStringNative = Void Function(Pointer<Char> value);
typedef _FreeStringDart = void Function(Pointer<Char> value);
