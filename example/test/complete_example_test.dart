import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_example/main.dart';

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
}
