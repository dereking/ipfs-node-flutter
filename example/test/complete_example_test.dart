import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:ipfs_node_example/main.dart';
import 'package:ipfs_node_example/pages/content_repository_page.dart';

final class _ExampleFakePlatform extends IpfsNodePlatform {
  @override
  Future<CapabilitySet> capabilities() async =>
      CapabilitySet([Capability.publicPublication]);

  @override
  Future<void> start(NodeConfig config) async {}

  @override
  Future<NodeStatus> status() async => const NodeStatus.running();

  @override
  Future<void> stop() async {}

  @override
  Future<IpfsAddResult> addBytes(Uint8List bytes) async =>
      IpfsAddResult(cid: 'bafkrei-example-added', bytes: bytes.length);
}

void main() {
  testWidgets('complete example exposes four capability-driven pages',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: CompleteIpfsExamplePage(
        autoStart: false,
        applicationSupportPath: '/tmp/ipfs-example-test',
      ),
    ));

    expect(find.text('节点配置'), findsWidgets);
    expect(find.text('公共网络'), findsOneWidget);
    expect(find.text('私有网络'), findsOneWidget);

    await tester.tap(find.text('私有网络'));
    await tester.pumpAndSettle();
    expect(find.text('Swarm Key（64 位十六进制）'), findsOneWidget);
    expect(find.text('生成密钥'), findsOneWidget);

    await tester.tap(find.text('内容与仓库'));
    await tester.pumpAndSettle();
    expect(find.text('添加内容'), findsOneWidget);
    expect(find.text('按 CID 取回内容'), findsOneWidget);
    expect(find.text('固定内容'), findsOneWidget);

    await tester.tap(find.text('网络与路由'));
    await tester.pumpAndSettle();
    expect(find.text('Swarm 连接'), findsOneWidget);
    expect(find.text('Bootstrap 节点'), findsOneWidget);
    expect(find.text('Peer 路由查询'), findsOneWidget);

    await tester.tap(find.text('IPNS 与诊断'));
    await tester.pumpAndSettle();
    expect(find.text('IPNS'), findsOneWidget);
    expect(find.text('运行全部演示'), findsOneWidget);
    expect(find.text('能力矩阵'), findsOneWidget);
    expect(find.text('操作日志'), findsOneWidget);
  });

  testWidgets('content repository hands an added CID to publication controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = IpfsNodeController(
      node: IpfsNode(platform: _ExampleFakePlatform()),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ContentRepositoryPage(
          controller: controller,
          repositoryPath: '/tmp/ipfs-example-test',
          pinCount: 0,
          publicationSupported: true,
        ),
      ),
    ));

    final addPanel = find.byType(IpfsContentAddPanel);
    await tester.enterText(
      find.descendant(of: addPanel, matching: find.byType(TextField)),
      'linked example',
    );
    await tester.tap(
      find.descendant(of: addPanel, matching: find.text('本地添加')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.controller?.text == 'bafkrei-example-added',
      ),
      findsOneWidget,
    );
  });
}
