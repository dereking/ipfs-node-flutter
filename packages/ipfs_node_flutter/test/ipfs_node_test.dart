import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

void main() {
  test('start delegates the supplied configuration to its backend', () async {
    final backend = _FakeBackend();
    final node = IpfsNode(backend: backend);
    const config = NodeConfig.private(
      swarmKey: [1, 2, 3],
      bootstrapPeers: ['peer-a'],
    );

    await node.start(config);

    expect(backend.startedWith, same(config));
    expect(await node.status(), const NodeStatus.running());
    expect(node.capabilities(), CapabilitySet([Capability.car]));
  });

  test('require throws a typed exception for unsupported capabilities', () {
    final node = IpfsNode(backend: _FakeBackend());

    expect(
      () => node.require(Capability.car),
      throwsA(
        isA<UnsupportedCapabilityException>()
            .having((error) => error.capability, 'capability', Capability.car),
      ),
    );
  });

  test('configuration values compare by value', () {
    expect(
      const NodeConfig.public(bootstrapPeers: ['peer-a']),
      const NodeConfig.public(bootstrapPeers: ['peer-a']),
    );
    expect(
      const NodeConfig.private(
        swarmKey: [1],
        allowedPeerIds: {'peer-a'},
      ),
      const NodeConfig.private(
        swarmKey: [1],
        allowedPeerIds: {'peer-a'},
      ),
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
  Future<NodeStatus> status() async => const NodeStatus.running();

  @override
  Future<CapabilitySet> capabilities() async => CapabilitySet([Capability.car]);
}
