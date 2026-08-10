import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';
import 'package:ipfs_node_flutter_web/ipfs_node_flutter_web.dart';
import 'package:web/web.dart' as web;

void main() => runApp(const _HeliaVerificationApp());

/// A browser-executable smoke test for the packaged Helia asset.
///
/// Run `flutter run -d chrome` from this example directory.  A successful
/// test renders `PASS` after the adapter loads, starts, adds bytes, reads them
/// back from IndexedDB, and stops the node.
final class _HeliaVerificationApp extends StatefulWidget {
  const _HeliaVerificationApp();

  @override
  State<_HeliaVerificationApp> createState() => _HeliaVerificationAppState();
}

final class _HeliaVerificationAppState extends State<_HeliaVerificationApp> {
  String _result = 'RUNNING';

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    final node = IpfsNodeFlutterWeb();
    var step = 'start';
    try {
      await node.start(NodeConfig.public());
      step = 'addBytes';
      final added = await node.addBytes(Uint8List.fromList([0, 1, 2, 255]));
      final cid = added.cid;
      step = 'getBytes';
      final bytes = await node.getBytes(cid);
      if (bytes.length != 4 || bytes[3] != 255) {
        throw StateError('Helia returned unexpected bytes.');
      }
      step = 'stop';
      await node.stop();
      if (await node.status() !=
          const NodeStatus(lifecycle: NodeLifecycle.stopped)) {
        throw StateError('Helia node did not stop.');
      }
      web.document.title = 'PASS: Helia browser integration';
      if (mounted) setState(() => _result = 'PASS');
    } catch (error) {
      web.document.title = 'FAIL: Helia browser integration at $step: $error';
      if (mounted) setState(() => _result = 'FAIL: $error');
    } finally {
      await node.stop();
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text(_result, key: const Key('helia-result'))),
      );
}
