import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';
import 'package:ipfs_node_flutter_web/ipfs_node_flutter_web.dart';

void main() {
  test('public startup creates a browser node and reports its transports',
      () async {
    final bridge = _FakeWebNodeBridge(
      capabilities: CapabilitySet([Capability.webRtc]),
    );
    final platform = IpfsNodeFlutterWeb(bridge: bridge);

    await platform.start(NodeConfig.public());

    expect(bridge.started, isTrue);
    expect(await platform.capabilities(), CapabilitySet([Capability.webRtc]));
    expect(
      await platform.status(),
      const NodeStatus.running(),
    );
  });

  test('private swarm-key configurations are rejected by the browser adapter',
      () async {
    final bridge = _FakeWebNodeBridge();
    final platform = IpfsNodeFlutterWeb(bridge: bridge);

    await expectLater(
      platform.start(NodeConfig.private(swarmKey: [1])),
      throwsA(
        isA<UnsupportedCapabilityException>().having(
          (error) => error.capability,
          'capability',
          Capability.privateSwarmKey,
        ),
      ),
    );
    expect(
      await platform.status(),
      const NodeStatus(lifecycle: NodeLifecycle.stopped),
    );
    expect(bridge.started, isFalse);
  });

  test('stop is idempotent after the browser node starts', () async {
    final bridge = _FakeWebNodeBridge();
    final platform = IpfsNodeFlutterWeb(bridge: bridge);
    await platform.start(NodeConfig.public());

    await platform.stop();
    await platform.stop();

    expect(
      await platform.status(),
      const NodeStatus(lifecycle: NodeLifecycle.stopped),
    );
    expect(bridge.stopCalls, 1);
  });

  test('addBytes and getBytes delegate to the Helia browser node', () async {
    final bridge = _FakeWebNodeBridge();
    final platform = IpfsNodeFlutterWeb(bridge: bridge);
    await platform.start(NodeConfig.public());

    final added = await platform.addBytes(Uint8List.fromList([1, 2, 3]));

    expect(added.cid, 'bafy-test');
    expect(added.bytes, 3);
    expect(await platform.getBytes(added.cid), [1, 2, 3]);
  });

  test('pin, swarm, bootstrap, and dht operations delegate to the bridge',
      () async {
    final bridge = _FakeWebNodeBridge();
    final platform = IpfsNodeFlutterWeb(bridge: bridge);
    await platform.start(NodeConfig.public());

    await platform.pin('bafkrei-pinned');
    expect(await platform.listPins(), hasLength(1));
    await platform.unpin('bafkrei-pinned');

    expect((await platform.swarmPeers()).single.id, 'QmPeer');

    await platform.bootstrapAdd('/dnsaddr/bootstrap.libp2p.io/p2p/QmX');
    expect(await platform.bootstrapList(),
        contains('/dnsaddr/bootstrap.libp2p.io/p2p/QmX'));
    await platform.bootstrapRemove('/dnsaddr/bootstrap.libp2p.io/p2p/QmX');

    expect((await platform.findProviders('bafkrei-x')).single.id, 'QmProvider');
    expect((await platform.findPeer('QmTarget')).id, 'QmTarget');
  });
  test('bitswap, IPNS, and keys delegate to the bridge', () async {
    final bridge = _FakeWebNodeBridge();
    final platform = IpfsNodeFlutterWeb(bridge: bridge);
    await platform.start(NodeConfig.public());

    final stats = await platform.bitswapStats();
    expect(stats.wantlist, 1);

    expect(await platform.publishName('bafkrei-x'), 'k51qzi5uqu5dgv');
    expect(
        await platform.resolveName('/ipns/k51qzi5uqu5dgv'), '/ipfs/bafkrei-x');
    expect((await platform.listKeys()).single.name, 'self');
  });

  test('registerWith installs a web backend factory', () {
    IpfsNodeFlutterWeb.registerWith();

    expect(IpfsNodePlatform.instance, isA<IpfsNodeFlutterWeb>());
  });
}

final class _FakeWebNodeBridge implements WebNodeBridge {
  _FakeWebNodeBridge({this.capabilities = const CapabilitySet.empty()});

  @override
  final CapabilitySet capabilities;
  bool started = false;
  int stopCalls = 0;

  @override
  Future<void> start({required List<String> bootstrapPeers}) async {
    started = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<String> addBytes(Uint8List bytes) async => 'bafy-test';

  @override
  Future<Uint8List> getBytes(String cid) async => Uint8List.fromList([1, 2, 3]);

  @override
  Future<void> pin(String cid) async {}

  @override
  Future<void> unpin(String cid) async {}

  @override
  Future<List<IpfsPinInfo>> listPins() async => const [
        IpfsPinInfo(cid: 'bafkrei-pinned', type: IpfsPinType.direct),
      ];

  @override
  Future<List<IpfsPeerInfo>> swarmPeers() async => const [
        IpfsPeerInfo(id: 'QmPeer', addrs: ['/ip4/1.2.3.4/tcp/4001'])
      ];

  @override
  Future<List<String>> bootstrapList() async =>
      const ['/dnsaddr/bootstrap.libp2p.io/p2p/QmX'];

  @override
  Future<void> bootstrapAdd(String multiaddr) async {}

  @override
  Future<void> bootstrapRemove(String multiaddr) async {}

  @override
  Future<List<IpfsPeerInfo>> findProviders(
    String cid, {
    Duration timeout = const Duration(seconds: 30),
  }) async =>
      const [IpfsPeerInfo(id: 'QmProvider')];

  @override
  Future<IpfsPeerInfo> findPeer(
    String peerId, {
    Duration timeout = const Duration(seconds: 30),
  }) async =>
      const IpfsPeerInfo(id: 'QmTarget');

  @override
  Future<String> publishName(
    String cid, {
    Duration timeout = const Duration(seconds: 60),
  }) async =>
      'k51qzi5uqu5dgv';

  @override
  Future<String> resolveName(
    String name, {
    Duration timeout = const Duration(seconds: 60),
  }) async =>
      '/ipfs/bafkrei-x';

  @override
  Future<List<IpfsKeyInfo>> listKeys() async =>
      const [IpfsKeyInfo(name: 'self', peerId: 'QmSelf')];

  @override
  Future<IpfsBitswapStats> bitswapStats() async => const IpfsBitswapStats(
        blocksReceived: 3,
        dataReceived: 10,
        wantlist: 1,
        messagesSent: 2,
        messagesReceived: 1,
      );
}
