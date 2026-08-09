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
      throwsA(isA<UnsupportedError>()),
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

    final cid = await platform.addBytes([1, 2, 3]);

    expect(cid, 'bafy-test');
    expect(await platform.getBytes(cid), [1, 2, 3]);
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
  Future<void> start() async {
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
}
