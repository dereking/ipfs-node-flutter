import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

/// Stable return codes from the packaged native node ABI.
enum NativeNodeErrorCode {
  ok(0),
  invalidHandle(1),
  invalidConfiguration(2),
  invalidState(3),
  invalidResponse(-1);

  const NativeNodeErrorCode(this.value);

  final int value;

  static NativeNodeErrorCode fromValue(int value) =>
      NativeNodeErrorCode.values.firstWhere(
        (code) => code.value == value,
        orElse: () => NativeNodeErrorCode.invalidResponse,
      );
}

/// Reports a native ABI error without exposing native implementation details.
final class NativeNodeException implements Exception {
  const NativeNodeException({
    required this.operation,
    required this.code,
    required this.message,
  });

  final String operation;
  final NativeNodeErrorCode code;
  final String message;

  @override
  String toString() => 'NativeNodeException($operation, $code): $message';
}

/// Narrow abstraction over the packaged C ABI.
///
/// This is public so host applications can substitute a deterministic ABI in
/// tests without loading a platform dynamic library.
abstract interface class NativeNodeAbi {
  NativeNodeErrorCode start(String request);

  NativeNodeErrorCode stop();

  String? status();

  String? capabilities();
}

/// Native [IpfsNodePlatform] implementation backed by the Go C ABI.
final class IpfsNodeFlutterNative extends IpfsNodePlatform {
  IpfsNodeFlutterNative({DynamicLibrary? library})
      : _abi = _FfiNativeNodeAbi(library ?? _openLibrary());

  IpfsNodeFlutterNative.forTesting(NativeNodeAbi abi) : _abi = abi;

  final NativeNodeAbi _abi;

  /// Installs this implementation as the active platform backend.
  static void registerWith({DynamicLibrary? library, NativeNodeAbi? abi}) {
    if (library != null && abi != null) {
      throw ArgumentError('Specify either library or abi, not both.');
    }
    IpfsNodePlatform.instance = abi == null
        ? IpfsNodeFlutterNative(library: library)
        : IpfsNodeFlutterNative.forTesting(abi);
  }

  @override
  Future<void> start(NodeConfig config) async {
    _throwForError('start', _abi.start(_encodeStartRequest(config)));
  }

  @override
  Future<void> stop() async {
    _throwForError('stop', _abi.stop());
  }

  @override
  Future<NodeStatus> status() async {
    final encoded = _requiredResponse('status', _abi.status());
    final map = _decodeObject('status', encoded);
    final lifecycleName = map['lifecycle'];
    if (lifecycleName is! String) {
      throw _invalidResponse('status', 'response did not contain lifecycle');
    }
    final lifecycle =
        NodeLifecycle.values.where((value) => value.name == lifecycleName);
    if (lifecycle.isEmpty) {
      throw _invalidResponse(
          'status', 'response contained an unknown lifecycle');
    }
    final safeDiagnostic = map['safeDiagnostic'];
    if (safeDiagnostic != null && safeDiagnostic is! String) {
      throw _invalidResponse(
          'status', 'response contained an invalid diagnostic');
    }
    return NodeStatus(
        lifecycle: lifecycle.single, safeDiagnostic: safeDiagnostic as String?);
  }

  @override
  Future<CapabilitySet> capabilities() async {
    final encoded = _requiredResponse('capabilities', _abi.capabilities());
    final decoded = _decodeJson('capabilities', encoded);
    if (decoded is! List || decoded.any((value) => value is! String)) {
      throw _invalidResponse('capabilities', 'response was not a string array');
    }
    final capabilities = <Capability>{};
    for (final name in decoded.cast<String>()) {
      for (final capability in Capability.values) {
        if (capability.name == name) capabilities.add(capability);
      }
    }
    return CapabilitySet(capabilities);
  }
}

String _encodeStartRequest(NodeConfig config) => switch (config) {
      PublicNodeConfig() => jsonEncode({'network': 'public'}),
      PrivateNodeConfig(:final swarmKey) => jsonEncode({
          'network': 'private',
          'swarmKey': base64Encode(swarmKey),
        }),
    };

String _requiredResponse(String operation, String? value) {
  if (value == null) {
    throw NativeNodeException(
      operation: operation,
      code: NativeNodeErrorCode.invalidHandle,
      message: 'Native node returned no response.',
    );
  }
  return value;
}

Map<String, dynamic> _decodeObject(String operation, String encoded) {
  final decoded = _decodeJson(operation, encoded);
  if (decoded is! Map<String, dynamic>) {
    throw _invalidResponse(operation, 'response was not an object');
  }
  return decoded;
}

dynamic _decodeJson(String operation, String encoded) {
  try {
    return jsonDecode(encoded);
  } on FormatException {
    throw _invalidResponse(operation, 'response was not valid JSON');
  }
}

NativeNodeException _invalidResponse(String operation, String message) =>
    NativeNodeException(
      operation: operation,
      code: NativeNodeErrorCode.invalidResponse,
      message: message,
    );

void _throwForError(String operation, NativeNodeErrorCode code) {
  if (code == NativeNodeErrorCode.ok) return;
  throw NativeNodeException(
    operation: operation,
    code: code,
    message: switch (code) {
      NativeNodeErrorCode.invalidHandle => 'Native node handle is invalid.',
      NativeNodeErrorCode.invalidConfiguration =>
        'Native node configuration is invalid.',
      NativeNodeErrorCode.invalidState =>
        'Native node lifecycle state is invalid.',
      NativeNodeErrorCode.invalidResponse =>
        'Native node returned an unknown error.',
      NativeNodeErrorCode.ok => '',
    },
  );
}

DynamicLibrary _openLibrary() {
  if (Platform.isIOS) return DynamicLibrary.process();
  final name = switch (Platform.operatingSystem) {
    'windows' => 'ipfs_node_core.dll',
    'linux' || 'android' => 'libipfs_node_core.so',
    _ => 'libipfs_node_core.dylib',
  };
  return DynamicLibrary.open(name);
}

final class _FfiNativeNodeAbi implements NativeNodeAbi {
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
      throw const NativeNodeException(
        operation: 'create',
        code: NativeNodeErrorCode.invalidHandle,
        message: 'Native node creation failed.',
      );
    }
  }

  final _CreateDart _create;
  final _StartDart _start;
  final _StopDart _stop;
  final _StringDart _status;
  final _StringDart _capabilities;
  final _FreeDart _free;
  final _FreeStringDart _freeString;
  late final int _handle;

  @override
  NativeNodeErrorCode start(String request) {
    final value = request.toNativeUtf8().cast<Char>();
    try {
      return NativeNodeErrorCode.fromValue(_start(_handle, value));
    } finally {
      calloc.free(value);
    }
  }

  @override
  NativeNodeErrorCode stop() => NativeNodeErrorCode.fromValue(_stop(_handle));

  @override
  String? status() => _readString(_status);

  @override
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

  void dispose() => _free(_handle);
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
