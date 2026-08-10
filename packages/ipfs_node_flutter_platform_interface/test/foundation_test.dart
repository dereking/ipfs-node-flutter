import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

void main() {
  test('provider routing is a distinct capability', () {
    expect(Capability.values, contains(Capability.providerRouting));
  });

  test('private config preserves repository and peer controls', () {
    final config = NodeConfig.private(
      repositoryPath: '/tmp/private-repo',
      swarmKey: List<int>.filled(32, 7),
      bootstrapPeers: const ['/ip4/127.0.0.1/tcp/4001/p2p/QmBootstrap'],
      relayPeers: const ['/ip4/127.0.0.1/tcp/4002/p2p/QmRelay'],
      allowedPeerIds: const {'QmBootstrap'},
    ) as PrivateNodeConfig;

    expect(config.repositoryPath, '/tmp/private-repo');
    expect(config.swarmKey, hasLength(32));
    expect(config.allowedPeerIds, {'QmBootstrap'});
  });

  test('private config requires a 32-byte swarm key', () {
    expect(
      () => NodeConfig.private(swarmKey: List<int>.filled(31, 1)),
      throwsArgumentError,
    );
  });

  test('default platform throws an unimplemented error that names start', () {
    expect(
      () => IpfsNodePlatform.instance.start(
        PublicNodeConfig(repositoryPath: '/tmp/ipfs-node-test'),
      ),
      throwsA(
        isA<UnimplementedError>().having(
          (error) => error.message,
          'message',
          contains('start'),
        ),
      ),
    );
  });

  test('default platform reports every backend operation as unimplemented',
      () async {
    final platform = IpfsNodePlatform.instance;

    // Stopping an unregistered platform is a safe no-op so teardown never
    // crashes when no implementation was installed.
    await platform.stop();

    await expectLater(
      platform.status(),
      throwsA(isA<UnimplementedError>().having(
        (error) => error.message,
        'message',
        contains('status'),
      )),
    );
    await expectLater(
      platform.capabilities(),
      throwsA(isA<UnimplementedError>().having(
        (error) => error.message,
        'message',
        contains('capabilities'),
      )),
    );
    await expectLater(
      platform.getBlock('bafk-test'),
      throwsA(isA<UnimplementedError>().having(
        (error) => error.message,
        'message',
        contains('getBlock'),
      )),
    );
  });

  test('node status exposes native public-network diagnostics by value', () {
    const first = NodeStatus.running(
      peerId: '12D3KooWtest',
      listenAddrs: ['/ip4/127.0.0.1/tcp/4001'],
      connectedPeers: ['12D3KooWbootstrap'],
      bootstrapErrors: ['unreachable'],
    );
    const second = NodeStatus.running(
      peerId: '12D3KooWtest',
      listenAddrs: ['/ip4/127.0.0.1/tcp/4001'],
      connectedPeers: ['12D3KooWbootstrap'],
      bootstrapErrors: ['unreachable'],
    );

    expect(first, second);
  });
}
