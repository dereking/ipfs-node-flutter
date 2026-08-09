import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter_native/ipfs_node_flutter_native.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

void main() {
  test('native adapter delegates lifecycle calls to the C ABI', () async {
    final abi = _FakeNativeNodeAbi();
    final platform = IpfsNodeFlutterNative.forTesting(abi);

    await platform.start(NodeConfig.private(swarmKey: [1, 2, 3]));

    expect(abi.startRequest, '{"network":"private","swarmKey":"AQID"}');
    expect(await platform.status(), const NodeStatus.running());
    expect(await platform.capabilities(), const CapabilitySet.empty());

    await platform.stop();
    expect(abi.stopped, isTrue);
  });

  test('native adapter maps ABI failures to a typed exception', () async {
    final platform = IpfsNodeFlutterNative.forTesting(
      _FakeNativeNodeAbi(startResult: NativeNodeErrorCode.invalidState),
    );

    await expectLater(
      platform.start(NodeConfig.public()),
      throwsA(
        isA<NativeNodeException>()
            .having((error) => error.operation, 'operation', 'start')
            .having(
              (error) => error.code,
              'code',
              NativeNodeErrorCode.invalidState,
            ),
      ),
    );
  });

  test('registerWith installs the native implementation', () {
    IpfsNodeFlutterNative.registerWith(
      abi: _FakeNativeNodeAbi(),
    );

    expect(IpfsNodePlatform.instance, isA<IpfsNodeFlutterNative>());
  });

  test(
    'native adapter runs the packaged host ABI',
    () async {
      final platform = IpfsNodeFlutterNative(
        library: DynamicLibrary.open(_hostLibrary.path),
      );

      await platform.start(NodeConfig.public());
      expect(await platform.status(), const NodeStatus.running());
      expect(await platform.capabilities(), const CapabilitySet.empty());

      await platform.stop();
      expect(await platform.status(),
          const NodeStatus(lifecycle: NodeLifecycle.stopped));
    },
    skip: !_hostLibrary.existsSync(),
  );
}

final _hostLibrary = File('native/go/dist/libipfs_node_core.dylib');

final class _FakeNativeNodeAbi implements NativeNodeAbi {
  _FakeNativeNodeAbi({this.startResult = NativeNodeErrorCode.ok});

  final NativeNodeErrorCode startResult;
  String? startRequest;
  bool stopped = false;

  @override
  NativeNodeErrorCode start(String request) {
    startRequest = request;
    return startResult;
  }

  @override
  NativeNodeErrorCode stop() {
    stopped = true;
    return NativeNodeErrorCode.ok;
  }

  @override
  String? status() => '{"lifecycle":"running"}';

  @override
  String? capabilities() => '[]';
}
