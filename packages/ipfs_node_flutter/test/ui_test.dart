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
}
