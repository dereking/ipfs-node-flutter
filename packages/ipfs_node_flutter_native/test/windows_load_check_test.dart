import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter_native/ipfs_node_flutter_native.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

void main() {
  test('windows ipfs_node_core.dll loads and exposes its ABI', () async {
    final libraryPath = Platform.environment['IPFS_NODE_CORE_DLL'];
    expect(libraryPath, isNotNull,
        reason: 'IPFS_NODE_CORE_DLL environment variable must be set');
    expect(File(libraryPath!).existsSync(), isTrue,
        reason: 'DLL file must exist at $libraryPath');

    IpfsNodeFlutterNative.registerWith(libraryPath: libraryPath);
    final platform = IpfsNodePlatform.instance;
    expect(platform, isA<IpfsNodeFlutterNative>());

    final capabilities = await platform.capabilities();
    expect(capabilities.contains(Capability.tcp), isTrue);
    expect(capabilities.contains(Capability.dhtRouting), isTrue);

    final status = await platform.status();
    expect(status.lifecycle, NodeLifecycle.stopped);
  });
}
