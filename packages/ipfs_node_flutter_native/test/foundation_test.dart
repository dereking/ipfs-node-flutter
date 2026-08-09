import 'dart:io';
import 'dart:convert';

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

      await platform.start(_offlinePublicConfig());
      final status = await platform.status();
      expect(status.lifecycle, NodeLifecycle.running);
      expect(status.peerId, isNotEmpty);
      expect(status.listenAddrs, isNotEmpty);
      expect(
        await platform.capabilities(),
        CapabilitySet([
          Capability.inboundListen,
          Capability.tcp,
          Capability.quic,
          Capability.dhtRouting,
        ]),
      );

      await platform.stop();
      expect(await platform.status(),
          const NodeStatus(lifecycle: NodeLifecycle.stopped));
    },
  );

  test('getBlock maps native retrieval failures to a typed operation error',
      () async {
    final platform = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
    await platform.start(_offlinePublicConfig());

    await expectLater(
      platform.getBlock('not-a-cid'),
      throwsA(isA<NativeNodeRequestException>()),
    );
    await platform.dispose();
  });

  test(
    'native adapter retrieves the documented CID from public IPFS',
    () async {
      final platform = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
      await platform.start(NodeConfig.public());
      addTearDown(platform.dispose);

      final status = await platform.status();
      expect(status.connectedPeers, isNotEmpty);
      final data = await platform.getBlock(
        'bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244',
      );
      expect(utf8.decode(data), 'Hello IPFS\n');
    },
    skip: Platform.environment['IPFS_PUBLIC_INTEGRATION'] == '1'
        ? false
        : 'set IPFS_PUBLIC_INTEGRATION=1 to use the public IPFS network',
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
      await first.start(_offlinePublicConfig());
      await second.start(_offlinePublicConfig());

      await first.dispose();

      expect((await second.status()).lifecycle, NodeLifecycle.running);
      await second.dispose();
    },
  );
}

NodeConfig _offlinePublicConfig() => NodeConfig.public(
      bootstrapPeers: const [
        '/ip4/127.0.0.1/tcp/1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN',
      ],
    );

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
