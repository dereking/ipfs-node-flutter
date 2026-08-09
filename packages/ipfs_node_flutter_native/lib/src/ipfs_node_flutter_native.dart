import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

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
    _throwForError('start', _backend.start(_encodeStartRequest(config)));
  }

  @override
  Future<void> stop() async {
    _throwForError('stop', _backend.stop());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _abi?.dispose();
  }

  @override
  Future<NodeStatus> status() async {
    final encoded = _requiredResponse('status', _backend.status());
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
    return NodeStatus(
      lifecycle: lifecycle.single,
      safeDiagnostic: safeDiagnostic as String?,
    );
  }

  @override
  Future<CapabilitySet> capabilities() async {
    final encoded = _requiredResponse('capabilities', _backend.capabilities());
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

  _FfiNativeNodeAbi get _backend {
    if (_disposed) {
      throw const NativeNodeInvalidHandleException(operation: 'node operation');
    }
    return _abi ??= _loadAbi(_libraryPath);
  }
}

String _encodeStartRequest(NodeConfig config) => switch (config) {
      PublicNodeConfig() => jsonEncode({'network': 'public'}),
      PrivateNodeConfig(:final swarmKey) => jsonEncode({
          'network': 'private',
          'swarmKey': base64Encode(swarmKey),
        }),
    };

_FfiNativeNodeAbi _loadAbi(String? libraryPath) {
  final artifact = libraryPath ?? _defaultArtifactName();
  try {
    final library = libraryPath == null && Platform.isIOS
        ? DynamicLibrary.process()
        : DynamicLibrary.open(artifact);
    return _FfiNativeNodeAbi(library);
  } catch (error) {
    throw NativeNodeLoadException(
      artifact: artifact,
      message: 'Unable to load native IPFS node artifact: $error',
    );
  }
}

String _defaultArtifactName() => switch (Platform.operatingSystem) {
      'windows' => 'ipfs_node_core.dll',
      'linux' || 'android' => 'libipfs_node_core.so',
      'ios' => 'iOS application process',
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
  _FfiNativeNodeAbi(DynamicLibrary library)
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
        _free =
            library.lookupFunction<_FreeNative, _FreeDart>('ipfs_node_free'),
        _freeString =
            library.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'ipfs_node_free_string',
        ) {
    _handle = _create();
    if (_handle == 0) {
      throw StateError('Native node creation returned an invalid handle.');
    }
  }

  final _CreateDart _create;
  final _StartDart _start;
  final _StopDart _stop;
  final _StringDart _status;
  final _StringDart _capabilities;
  final _FreeDart _free;
  final _FreeStringDart _freeString;
  late int _handle;

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
typedef _FreeNative = Void Function(UintPtr handle);
typedef _FreeDart = void Function(int handle);
typedef _FreeStringNative = Void Function(Pointer<Char> value);
typedef _FreeStringDart = void Function(Pointer<Char> value);
