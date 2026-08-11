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

  test('native startup requires a persistent repository path', () async {
    final node = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
    addTearDown(node.dispose);

    await expectLater(
      node.start(NodeConfig.public()),
      throwsA(isA<NativeNodeInvalidConfigurationException>()),
    );
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
          Capability.providerRouting,
          Capability.publicPublication,
        ]),
      );

      await platform.stop();
      expect(await platform.status(),
          const NodeStatus(lifecycle: NodeLifecycle.stopped));
    },
  );

  test('native adapter starts a persistent private node with peer controls',
      () async {
    final platform = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
    const bootstrap =
        '/ip4/127.0.0.1/tcp/1/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN';
    await platform.start(NodeConfig.private(
      repositoryPath:
          Directory.systemTemp.createTempSync('ipfs-private-test-').path,
      swarmKey: List<int>.filled(32, 9),
      bootstrapPeers: const [bootstrap],
      relayPeers: const [bootstrap],
      allowedPeerIds: const {
        'QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN',
      },
    ));
    addTearDown(platform.dispose);

    expect((await platform.status()).lifecycle, NodeLifecycle.running);
    expect(await platform.bootstrapList(), const [bootstrap]);
    expect(
      await platform.capabilities(),
      CapabilitySet([
        Capability.inboundListen,
        Capability.tcp,
        Capability.quic,
        Capability.dhtRouting,
        Capability.privateSwarmKey,
        Capability.providerRouting,
      ]),
    );
  });

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

  test('native adapter adds content, pins it, and lists pins', () async {
    final platform = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
    await platform.start(_offlinePublicConfig());
    addTearDown(platform.dispose);

    const content = 'Hello IPFS\n';
    final added = await platform.addBytes(utf8.encode(content));
    expect(added.cid,
        'bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244');
    expect(added.bytes, content.length);

    final block = await platform.getBlock(added.cid);
    expect(utf8.decode(block), content);

    await platform.startProviding(added.cid);
    final publication = await platform.publicationStatus(added.cid);
    expect(publication.cid, added.cid);
    expect(
      publication.state,
      anyOf(IpfsPublicationState.pending, IpfsPublicationState.failed),
    );
    expect(
      await platform.listPublicationStatuses(),
      contains(predicate<IpfsPublicationStatus>(
        (status) => status.cid == added.cid,
      )),
    );

    await expectLater(
      platform.addAndProvide(utf8.encode('durable publication failure')),
      throwsA(
        isA<IpfsPublicationException>().having(
          (error) => error.result.cid,
          'durable CID',
          isNotEmpty,
        ),
      ),
    );

    await platform.pin(added.cid);
    final pins = await platform.listPins();
    expect(
      pins,
      contains(predicate<IpfsPinInfo>((pin) => pin.cid == added.cid)),
    );

    await platform.unpin(added.cid);
    expect(await platform.listPins(), isEmpty);
  });

  test('native adapter exposes swarm, bootstrap, bitswap, and keys', () async {
    final platform = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
    await platform.start(_offlinePublicConfig());
    addTearDown(platform.dispose);

    expect(await platform.swarmPeers(), isEmpty);

    const extra =
        '/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN';
    await platform.bootstrapAdd(extra);
    expect(await platform.bootstrapList(), contains(extra));
    await platform.bootstrapRemove(extra);
    expect(await platform.bootstrapList(), isNot(contains(extra)));

    final stats = await platform.bitswapStats();
    expect(stats.blocksReceived, 0);

    final keys = await platform.listKeys();
    expect(keys, hasLength(1));
    expect(keys.single.name, 'self');

    final status = await platform.status();
    final self = await platform.findPeer(status.peerId!);
    expect(self.id, status.peerId);
  });

  test(
    'native adapter retrieves the documented CID from public IPFS',
    () async {
      final platform = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
      await platform.start(_offlinePublicConfig());
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
        platform.start(_offlinePublicConfig()),
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
    'second native adapter reports the process singleton error',
    () async {
      final first = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
      final second = IpfsNodeFlutterNative(libraryPath: hostLibrary.path);
      await first.start(_offlinePublicConfig());
      await expectLater(
        second.start(_offlinePublicConfig()),
        throwsA(isA<NativeNodeAlreadyRunningException>()),
      );
      await first.dispose();
      await second.dispose();
    },
  );
}

NodeConfig _offlinePublicConfig() => NodeConfig.public(
      repositoryPath:
          Directory.systemTemp.createTempSync('ipfs-node-flutter-test-').path,
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
