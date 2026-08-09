import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:ipfs_node_flutter_native/ipfs_node_flutter_native.dart';

const _documentedCid =
    'bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244';
const _documentedContent = 'Hello IPFS\n';
const _unreachableBootstrapPeer = '/ip4/127.0.0.1/tcp/1/p2p/'
    'QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN';

void main() {
  late final File hostLibrary;

  setUpAll(() {
    hostLibrary = _packagedHostLibrary();
    expect(
      hostLibrary.existsSync(),
      isTrue,
      reason: 'Run `make build-host` in native/go before this test.',
    );
    IpfsNodeFlutterNative.registerWith(libraryPath: hostLibrary.path);
  });

  test('public SDK starts a real isolated libp2p node and stops cleanly',
      () async {
    final node = IpfsNode();
    addTearDown(node.dispose);

    await node.start(_offlinePublicConfig());

    final status = await node.status();
    expect(status.lifecycle, NodeLifecycle.running);
    expect(status.peerId, isNotEmpty);
    expect(status.listenAddrs, isNotEmpty);
    expect(status.bootstrapErrors, isNotEmpty);

    final capabilities = await node.capabilities();
    expect(
      capabilities,
      CapabilitySet({
        Capability.inboundListen,
        Capability.tcp,
        Capability.quic,
        Capability.dhtRouting,
      }),
    );
    expect(() => node.require(Capability.inboundListen), returnsNormally);

    await node.stop();
    expect(
      await node.status(),
      const NodeStatus(lifecycle: NodeLifecycle.stopped),
    );
  });

  test('public SDK maps an invalid CID to a typed native request error',
      () async {
    final node = IpfsNode();
    addTearDown(node.dispose);
    await node.start(_offlinePublicConfig());

    await expectLater(
      node.getBlock('not-a-cid'),
      throwsA(
        isA<NativeNodeRequestException>()
            .having((error) => error.operation, 'operation', 'getBlock'),
      ),
    );
  });

  test('two public SDK nodes own different native identities', () async {
    final first = IpfsNode();
    final second = IpfsNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await first.start(_offlinePublicConfig());
    await second.start(_offlinePublicConfig());

    final firstStatus = await first.status();
    final secondStatus = await second.status();
    expect(firstStatus.peerId, isNot(secondStatus.peerId));

    await first.dispose();
    expect((await second.status()).lifecycle, NodeLifecycle.running);
  });

  test(
    'public SDK retrieves and verifies a documented CID over DHT and Bitswap',
    () async {
      final node = IpfsNode();
      addTearDown(node.dispose);

      await node.start(NodeConfig.public());
      final status = await node.status();
      expect(status.lifecycle, NodeLifecycle.running);
      expect(status.connectedPeers, isNotEmpty);

      final bytes = await node.getBlock(_documentedCid);
      expect(utf8.decode(bytes), _documentedContent);
    },
    skip: Platform.environment['IPFS_PUBLIC_INTEGRATION'] == '1'
        ? false
        : 'set IPFS_PUBLIC_INTEGRATION=1 to use the public IPFS network',
  );
}

NodeConfig _offlinePublicConfig() => NodeConfig.public(
      bootstrapPeers: const [_unreachableBootstrapPeer],
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
    if (parent.path == directory.path) return candidate;
    directory = parent;
  }
}
