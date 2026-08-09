import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';
import 'package:ipfs_node_flutter_web/ipfs_node_flutter_web.dart';

void main() {
  test('public startup reports the explicit no-Helia degraded fallback',
      () async {
    final platform = IpfsNodeFlutterWeb();

    await platform.start(NodeConfig.public());

    expect(await platform.capabilities(), const CapabilitySet.empty());
    expect(
      await platform.status(),
      const NodeStatus(
        lifecycle: NodeLifecycle.degraded,
        safeDiagnostic: 'Web IPFS support requires the Helia backend.',
      ),
    );
  });

  test('private swarm-key configurations are rejected without Helia',
      () async {
    final platform = IpfsNodeFlutterWeb();

    await expectLater(
      platform.start(NodeConfig.private(swarmKey: [1])),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      await platform.status(),
      const NodeStatus(lifecycle: NodeLifecycle.stopped),
    );
  });

  test('stop is idempotent after the degraded fallback starts', () async {
    final platform = IpfsNodeFlutterWeb();
    await platform.start(NodeConfig.public());

    await platform.stop();
    await platform.stop();

    expect(
      await platform.status(),
      const NodeStatus(lifecycle: NodeLifecycle.stopped),
    );
  });

  test('registerWith installs a web backend factory', () {
    IpfsNodeFlutterWeb.registerWith();

    expect(IpfsNodePlatform.instance, isA<IpfsNodeFlutterWeb>());
  });
}
