import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:ipfs_node_example/feature_checks.dart' show documentedCid;
import 'package:ipfs_node_example/main.dart';

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
  testWidgets('shows the IPFS feature lab with test and feature tabs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: IpfsFeatureLabPage(autoStart: false)),
    );

    expect(find.text('IPFS 功能验证'), findsOneWidget);
    expect(find.text('功能测试'), findsOneWidget);
    expect(find.text('常用功能'), findsOneWidget);

    expect(find.text('节点状态'), findsOneWidget);
    expect(find.text('节点生命周期'), findsOneWidget);
    expect(find.text('公网取回固定内容'), findsOneWidget);
    expect(find.textContaining(documentedCid), findsOneWidget);
    expect(find.text('运行'), findsNWidgets(5));

    await tester.tap(find.text('常用功能'));
    await tester.pumpAndSettle();

    expect(find.text('节点控制'), findsOneWidget);
    expect(find.text('按 CID 取回内容'), findsOneWidget);
    expect(find.text('启动'), findsOneWidget);
    expect(find.text('获取'), findsOneWidget);
    expect(find.text('添加内容'), findsOneWidget);
    expect(find.text('固定内容'), findsOneWidget);
    expect(find.text('固定列表'), findsOneWidget);
    expect(find.text('Swarm 连接'), findsOneWidget);
    expect(find.text('Bootstrap 节点'), findsOneWidget);
    expect(find.text('Bitswap 统计'), findsOneWidget);
    expect(find.text('DHT Providers'), findsOneWidget);
    expect(find.text('IPNS'), findsOneWidget);
  });

  testWidgets('feature lab hands an added CID to publication controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    IpfsNodePlatform.instance = _ExampleFakePlatform();
    await tester.pumpWidget(
      const MaterialApp(home: IpfsFeatureLabPage(autoStart: false)),
    );
    await tester.tap(find.text('常用功能'));
    await tester.pumpAndSettle();

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
