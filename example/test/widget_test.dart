import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_example/main.dart';

void main() {
  testWidgets('shows the public IPFS connectivity check', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PublicIpfsCheckPage(autoStart: false)),
    );

    expect(find.text('macOS 公共 IPFS 节点验证'), findsOneWidget);
    expect(find.text('重新验证'), findsOneWidget);
    expect(find.textContaining(documentedCid), findsOneWidget);
  });
}
