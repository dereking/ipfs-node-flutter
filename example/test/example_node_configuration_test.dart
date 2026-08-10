import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_example/example_node_configuration.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

void main() {
  test('private key parsing requires exactly 64 hexadecimal characters', () {
    expect(
      ExampleNodeConfiguration.parseSwarmKey(List.filled(32, '0a').join()),
      List<int>.filled(32, 10),
    );
    expect(
      () => ExampleNodeConfiguration.parseSwarmKey('0a'),
      throwsFormatException,
    );
    expect(
      () =>
          ExampleNodeConfiguration.parseSwarmKey(List.filled(32, 'zz').join()),
      throwsFormatException,
    );
  });

  test('generated private keys contain 32 bytes of hexadecimal data', () {
    final generated = ExampleNodeConfiguration.generateSwarmKeyHex(Random(7));
    expect(generated, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(ExampleNodeConfiguration.parseSwarmKey(generated), hasLength(32));
  });

  test('repository paths are stable and isolated by network and key', () {
    const firstKey =
        '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
    const secondKey =
        '101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f';
    const public = ExampleNodeConfiguration.public();
    const first = ExampleNodeConfiguration.private(swarmKeyHex: firstKey);
    const same = ExampleNodeConfiguration.private(swarmKeyHex: firstKey);
    const second = ExampleNodeConfiguration.private(swarmKeyHex: secondKey);

    expect(
        public.repositoryPath('/app/support'), '/app/support/ipfs-node/public');
    expect(first.repositoryPath('/app/support'),
        same.repositoryPath('/app/support'));
    expect(first.repositoryPath('/app/support'),
        isNot(second.repositoryPath('/app/support')));
    expect(first.maskedSwarmKey, isNot(contains(firstKey.substring(0, 8))));
  });

  test('private configuration builds every SDK peer control', () {
    const key =
        '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
    const configuration = ExampleNodeConfiguration.private(
      swarmKeyHex: key,
      bootstrapPeers: ['bootstrap'],
      relayPeers: ['relay'],
      allowedPeerIds: {'peer'},
    );

    final result = configuration.build('/app/support') as PrivateNodeConfig;
    expect(result.repositoryPath, configuration.repositoryPath('/app/support'));
    expect(result.bootstrapPeers, ['bootstrap']);
    expect(result.relayPeers, ['relay']);
    expect(result.allowedPeerIds, {'peer'});
  });
}
