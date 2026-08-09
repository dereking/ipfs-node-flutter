import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

void main() {
  test('start delegates the supplied configuration to the installed platform',
      () async {
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

  test('each default node receives its own backend instance', () async {
    final factory = _FactoryPlatform();
    IpfsNodePlatform.instance = factory;
    final first = IpfsNode();
    final second = IpfsNode();

    await first.start(NodeConfig.public());
    await second.start(NodeConfig.public());

    expect(factory.created, hasLength(2));
    expect(factory.created[0].startedWith, isNotNull);
    expect(factory.created[1].startedWith, isNotNull);
    expect(identical(factory.created[0], factory.created[1]), isFalse);
  });

  test('require throws a typed exception for unsupported capabilities',
      () async {
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

  test('public configuration copies bootstrap peers from the caller', () {
    final bootstrapPeers = ['peer-a'];
    final config = NodeConfig.public(bootstrapPeers: bootstrapPeers);

    bootstrapPeers.add('peer-b');

    expect((config as PublicNodeConfig).bootstrapPeers, ['peer-a']);
    expect(
      () => config.bootstrapPeers.add('peer-c'),
      throwsUnsupportedError,
    );
  });

  test('getBlock delegates CID retrieval to the backend', () async {
    final platform = _FakePlatform(block: [1, 2, 3]);
    final node = IpfsNode(platform: platform);

    expect(await node.getBlock('bafk-test'), [1, 2, 3]);
    expect(platform.requestedCid, 'bafk-test');
  });
}

final class _FakePlatform extends IpfsNodePlatform {
  _FakePlatform({
    this.availableCapabilities = const CapabilitySet.empty(),
    this.block = const [],
  });

  final CapabilitySet availableCapabilities;
  final List<int> block;
  NodeConfig? startedWith;
  String? requestedCid;

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

  @override
  Future<Uint8List> getBlock(
    String cid, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    requestedCid = cid;
    return Uint8List.fromList(block);
  }
}

final class _FactoryPlatform extends IpfsNodePlatform {
  final List<_FakePlatform> created = [];

  @override
  IpfsNodePlatform create() {
    final platform = _FakePlatform();
    created.add(platform);
    return platform;
  }

  @override
  Future<CapabilitySet> capabilities() => throw UnimplementedError();

  @override
  Future<void> start(NodeConfig config) => throw UnimplementedError();

  @override
  Future<NodeStatus> status() => throw UnimplementedError();

  @override
  Future<void> stop() => throw UnimplementedError();

  @override
  Future<Uint8List> getBlock(
    String cid, {
    Duration timeout = const Duration(seconds: 90),
  }) =>
      throw UnimplementedError();
}
