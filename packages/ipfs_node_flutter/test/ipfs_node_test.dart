import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

void main() {
  test('start delegates the supplied configuration to its backend', () async {
    NodeConfig? startedWith;
    final node = IpfsNode.forTesting(
      onStart: (config) async => startedWith = config,
      onStop: () async {},
      onStatus: () async => const NodeStatus.running(),
      onCapabilities: () async => CapabilitySet([Capability.car]),
    );
    final config = NodeConfig.private(
      swarmKey: [1, 2, 3],
      bootstrapPeers: ['peer-a'],
    );

    await node.start(config);

    expect(startedWith, same(config));
    expect(await node.status(), const NodeStatus.running());
    expect(await node.capabilities(), CapabilitySet([Capability.car]));
  });

  test('require throws a typed exception for unsupported capabilities', () {
    final node = _nodeWithoutCapabilities();

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
      NodeConfig.public(bootstrapPeers: ['peer-a']),
      NodeConfig.public(bootstrapPeers: ['peer-a']),
    );
    expect(
      NodeConfig.private(
        swarmKey: [1],
        allowedPeerIds: {'peer-a'},
      ),
      NodeConfig.private(
        swarmKey: [1],
        allowedPeerIds: {'peer-a'},
      ),
    );
  });

  test('private configuration rejects an empty swarm key', () {
    expect(
      () => NodeConfig.private(swarmKey: []),
      throwsArgumentError,
    );
  });

  test('configuration collection values are defensively copied', () {
    final swarmKey = [1];
    final peerIds = {'peer-a'};
    final config = NodeConfig.private(
      swarmKey: swarmKey,
      allowedPeerIds: peerIds,
    );

    swarmKey[0] = 2;
    peerIds.add('peer-b');

    final privateConfig = config as PrivateNodeConfig;
    expect(privateConfig.swarmKey, [1]);
    expect(privateConfig.allowedPeerIds, {'peer-a'});
  });
}

IpfsNode _nodeWithoutCapabilities() => IpfsNode.forTesting(
      onStart: (_) async {},
      onStop: () async {},
      onStatus: () async => const NodeStatus.running(),
      onCapabilities: () async => const CapabilitySet.empty(),
    );
