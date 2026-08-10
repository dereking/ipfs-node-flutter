import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

final class _FakeNodePlatform extends IpfsNodePlatform {
  @override
  Future<CapabilitySet> capabilities() async => const CapabilitySet.empty();

  @override
  Future<void> start(NodeConfig config) async {}

  @override
  Future<NodeStatus> status() async =>
      const NodeStatus.running(peerId: 'QmFake');

  @override
  Future<void> stop() async {}

  @override
  Future<Uint8List> getBlock(
    String cid, {
    Duration timeout = const Duration(seconds: 180),
  }) async =>
      Uint8List.fromList(utf8.encode('Hello IPFS\n'));

  @override
  Future<IpfsAddResult> addBytes(Uint8List bytes) async =>
      IpfsAddResult(cid: 'bafkrei-added-${bytes.length}', bytes: bytes.length);

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
        IpfsPeerInfo(id: 'QmPeerA', addrs: ['/ip4/1.2.3.4/tcp/4001'])
      ];

  @override
  Future<void> swarmConnect(String multiaddr) async {}

  @override
  Future<void> swarmDisconnect(String peerId) async {}

  @override
  Future<List<String>> bootstrapList() async =>
      const ['/dnsaddr/bootstrap.libp2p.io/p2p/QmX'];

  @override
  Future<void> bootstrapAdd(String multiaddr) async {}

  @override
  Future<void> bootstrapRemove(String multiaddr) async {}

  @override
  Future<IpfsBitswapStats> bitswapStats() async => const IpfsBitswapStats(
        blocksReceived: 3,
        dataReceived: 10,
        wantlist: 0,
        messagesSent: 2,
        messagesReceived: 1,
      );

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
}

void main() {
  setUp(() {
    IpfsNodePlatform.instance = _FakeNodePlatform();
  });

  testWidgets('IpfsFeatureCheckCard reports a passing check', (tester) async {
    final check = IpfsFeatureCheck(
      title: 'Sample',
      description: 'A sample check.',
      run: (_) async => 'all good',
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: IpfsFeatureCheckCard(check: check))),
    );

    expect(find.text('Sample'), findsOneWidget);
    expect(find.text('运行'), findsOneWidget);

    await tester.tap(find.text('运行'));
    await tester.pumpAndSettle();

    expect(find.textContaining('通过'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('IpfsFeatureCheckCard surfaces a failing check', (tester) async {
    final check = IpfsFeatureCheck(
      title: 'Boom',
      description: 'Always fails.',
      run: (_) async => throw StateError('boom'),
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: IpfsFeatureCheckCard(check: check))),
    );

    await tester.tap(find.text('运行'));
    await tester.pumpAndSettle();

    expect(find.textContaining('失败'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('IpfsFeatureCheckList renders every check', (tester) async {
    final checks = [
      IpfsFeatureCheck(
          title: 'One', description: 'First.', run: (_) async => '1'),
      IpfsFeatureCheck(
          title: 'Two', description: 'Second.', run: (_) async => '2'),
    ];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: IpfsFeatureCheckList(checks: checks))),
    );

    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('运行'), findsNWidgets(2));
  });

  testWidgets('IpfsNodeStatusPanel renders lifecycle and peer information',
      (tester) async {
    const status = NodeStatus.running(
      peerId: 'QmPeer',
      listenAddrs: ['/ip4/127.0.0.1/tcp/4001'],
      connectedPeers: ['QmPeerA'],
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: IpfsNodeStatusPanel(status: status))),
    );

    expect(find.text('running'), findsOneWidget);
    expect(find.text('QmPeer'), findsOneWidget);
    expect(find.text('1 个'), findsNWidgets(2));
  });

  testWidgets('IpfsNodeStatusPanel shows its error state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: IpfsNodeStatusPanel(status: null)),
      ),
    );

    expect(find.text('节点未启动'), findsOneWidget);
  });

  testWidgets('IpfsNodeLifecyclePanel starts a node through its controller',
      (tester) async {
    final controller = IpfsNodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IpfsNodeLifecyclePanel(controller: controller)),
      ),
    );

    expect(find.text('节点控制'), findsOneWidget);
    expect(find.text('启动'), findsOneWidget);

    await tester.tap(find.text('启动'));
    await tester.pumpAndSettle();

    expect(find.text('停止'), findsOneWidget);
    expect(find.text('QmFake'), findsOneWidget);
  });

  testWidgets('IpfsCidFetchPanel fetches and decodes a block', (tester) async {
    final controller = IpfsNodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IpfsCidFetchPanel(controller: controller)),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244',
    );
    await tester.tap(find.text('获取'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hello IPFS'), findsOneWidget);
    expect(find.textContaining('成功'), findsOneWidget);
  });

  testWidgets('IpfsContentAddPanel adds text and shows the CID',
      (tester) async {
    final controller = IpfsNodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IpfsContentAddPanel(controller: controller)),
      ),
    );

    await tester.enterText(find.byType(TextField), 'some text');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.textContaining('bafkrei-added-9'), findsOneWidget);
    expect(find.text('复制 CID'), findsOneWidget);
  });

  testWidgets('IpfsPinPanel pins and unpins a CID', (tester) async {
    final controller = IpfsNodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: IpfsPinPanel(controller: controller))),
    );

    await tester.enterText(find.byType(TextField), 'bafkrei-target');
    await tester.tap(find.text('固定'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已固定'), findsOneWidget);

    await tester.tap(find.text('取消固定'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已取消固定'), findsOneWidget);
  });

  testWidgets('IpfsPinListPanel renders pinned roots', (tester) async {
    final controller = IpfsNodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
          home: Scaffold(body: IpfsPinListPanel(controller: controller))),
    );
    await tester.pumpAndSettle();

    expect(find.text('固定列表'), findsOneWidget);
    expect(find.text('bafkrei-pinned'), findsOneWidget);
  });

  testWidgets('IpfsSwarmPanel renders peers', (tester) async {
    final controller = IpfsNodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IpfsSwarmPanel(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Swarm 连接'), findsOneWidget);
    expect(find.text('QmPeerA'), findsOneWidget);
  });

  testWidgets('IpfsBootstrapPanel renders bootstrap peers', (tester) async {
    final controller = IpfsNodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IpfsBootstrapPanel(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bootstrap 节点'), findsOneWidget);
    expect(find.text('/dnsaddr/bootstrap.libp2p.io/p2p/QmX'), findsOneWidget);
  });

  testWidgets('IpfsBitswapPanel renders counters', (tester) async {
    final controller = IpfsNodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IpfsBitswapPanel(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bitswap 统计'), findsOneWidget);
    expect(find.text('收到块'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('IpfsDhtPanel queries providers', (tester) async {
    final controller = IpfsNodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: IpfsDhtPanel(controller: controller))),
    );

    await tester.enterText(find.byType(TextField), 'bafkrei-prov');
    await tester.tap(find.text('查询'));
    await tester.pumpAndSettle();

    expect(find.text('QmProvider'), findsOneWidget);
  });

  testWidgets('IpfsIpnsPanel publishes and resolves', (tester) async {
    final controller = IpfsNodeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: IpfsIpnsPanel(controller: controller))),
    );

    await tester.enterText(find.byType(TextField).first, 'bafkrei-content');
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已发布'), findsOneWidget);

    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    expect(find.textContaining('解析结果'), findsOneWidget);
  });
}
