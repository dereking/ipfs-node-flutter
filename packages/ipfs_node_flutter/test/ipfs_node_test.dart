import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

void main() {
  test('start delegates the supplied configuration to the installed platform', () async {
    final platform =
        _FakePlatform(availableCapabilities: CapabilitySet([Capability.car]));
    IpfsNodePlatform.instance = platform;
    final node = IpfsNode();
    final config = NodeConfig.private(
      swarmKey: [1, 2, 3],
      bootstrapPeers: ['peer-a'],
    );

    await node.start(config);

    expect(platform.startedWith, same(config));
    expect(await node.status(), const NodeStatus.running());
    expect(await node.capabilities(), CapabilitySet([Capability.car]));
  });

  test('require throws a typed exception for unsupported capabilities', () async {
    final node = IpfsNode(platform: _FakePlatform());
    await node.capabilities();

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

  test('direct private configuration rejects an empty swarm key', () {
    expect(
      () => PrivateNodeConfig(swarmKey: []),
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

final class _FakePlatform extends IpfsNodePlatform {
  _FakePlatform({this.availableCapabilities = const CapabilitySet.empty()});

  final CapabilitySet availableCapabilities;
  NodeConfig? startedWith;

  @override
  Future<CapabilitySet> capabilities() async => availableCapabilities;

  @override
  Future<void> start(NodeConfig config) async {
    startedWith = config;
  }

  @override
  Future<NodeStatus> status() async => const NodeStatus.running();

  @override
  Future<void> stop() async {}
}
