import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter_native/ipfs_node_flutter_native.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

void main() {
  late final File hostLibrary;

  setUpAll(() async {
    hostLibrary = _packagedHostLibrary();
    expect(
      hostLibrary.existsSync(),
      isTrue,
      reason: 'Run `make build-host` in native/go before testing the adapter.',
    );
  });

  test('registerWith installs a native backend factory', () {
    IpfsNodeFlutterNative.registerWith(libraryPath: hostLibrary.path);

    expect(IpfsNodePlatform.instance, isA<IpfsNodeFlutterNative>());
  });

  test(
    'native adapter runs the packaged host ABI',
    () async {
      final platform = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);

      await platform.start(NodeConfig.public());
      expect(await platform.status(), const NodeStatus.running());
      expect(await platform.capabilities(), const CapabilitySet.empty());

      await platform.stop();
      expect(await platform.status(),
          const NodeStatus(lifecycle: NodeLifecycle.stopped));
    },
  );

  test(
    'disposing a native adapter maps subsequent calls to a typed handle error',
    () async {
      final platform = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
      await platform.dispose();

      await expectLater(
        platform.start(NodeConfig.public()),
        throwsA(isA<NativeNodeInvalidHandleException>()),
      );
    },
  );

  test('loading a missing native artifact reports its path', () async {
    const artifact = 'missing/libipfs_node_core.dylib';

    await expectLater(
      IpfsNodeFlutterNative(libraryPath: artifact).status(),
      throwsA(
        isA<NativeNodeLoadException>()
            .having((error) => error.artifact, 'artifact', artifact),
      ),
    );
  });

  test(
    'separate native adapters own independent handles',
    () async {
      final first = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
      final second = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
      await first.start(NodeConfig.public());
      await second.start(NodeConfig.public());

      await first.dispose();

      expect(await second.status(), const NodeStatus.running());
      await second.dispose();
    },
  );
}

File _packagedHostLibrary() {
  var directory = Directory.current;
  while (true) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}native${Platform.pathSeparator}go'
      '${Platform.pathSeparator}dist${Platform.pathSeparator}libipfs_node_core.dylib',
    );
    if (candidate.existsSync()) return candidate;

    final parent = directory.parent;
    if (parent.path == directory.path) {
      return candidate;
    }
    directory = parent;
  }
}
