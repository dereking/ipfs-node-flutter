import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_example/feature_checks.dart' show documentedCid;
import 'package:ipfs_node_example/main.dart';

void main() {
  testWidgets('shows the IPFS feature lab with test and feature tabs',
      (tester) async {
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
  });
}
