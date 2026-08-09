import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:ipfs_node_flutter/src/ipfs_node_backend.dart';

void main() {
  test('start delegates the supplied configuration to its backend', () async {
    final backend = _FakeBackend();
    final node = IpfsNode.forTesting(backend);
    final config = NodeConfig.privateNetwork(
      swarmKey: 'private-swarm-key',
      bootstrapPeers: ['peer-a'],
    );

    await node.start(config);

    expect(backend.startedWith, same(config));
  });

  test('require throws a typed exception for unsupported capabilities', () {
    final node = IpfsNode.forTesting(_FakeBackend());

    expect(
      () => node.require(Capability.car),
      throwsA(
        isA<UnsupportedCapabilityException>()
            .having((error) => error.capability, 'capability', Capability.car),
      ),
    );
  });

  test('private network requires a nonempty swarm key', () {
    expect(
      () => NodeConfig.privateNetwork(swarmKey: ''),
      throwsArgumentError,
    );
  });
}

final class _FakeBackend implements IpfsNodeBackend {
  NodeConfig? startedWith;

  @override
  Future<void> start(NodeConfig config) async {
    startedWith = config;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<NodeStatus> status() async => const NodeStatus(
        lifecycle: NodeLifecycle.stopped,
      );

  @override
  Future<Set<Capability>> capabilities() async => const {};
}
