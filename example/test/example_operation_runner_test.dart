import 'package:flutter_test/flutter_test.dart';
import 'package:ipfs_node_example/example_operation_runner.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

void main() {
  test('run all executes local and routed operations in dependency order',
      () async {
    final platform = _RecordingOperations(ready: true);
    final runner = ExampleOperationRunner();

    final entries = await runner.run(platform);

    expect(
      platform.calls,
      [
        'add',
        'get',
        'pin',
        'listPins',
        'networkReady',
        'provide',
        'findProviders',
        'publishName',
        'resolveName',
        'bitswapStats',
      ],
    );
    expect(
        entries,
        everyElement(
          isA<ExampleOperationLogEntry>().having(
            (entry) => entry.state,
            'state',
            ExampleOperationState.passed,
          ),
        ));
    expect(entries.every((entry) => entry.elapsed >= Duration.zero), isTrue);
  });

  test('run all marks routed operations waiting when network is not ready',
      () async {
    final platform = _RecordingOperations(ready: false);
    final entries = await ExampleOperationRunner().run(platform);

    expect(platform.calls, contains('bitswapStats'));
    expect(platform.calls, isNot(contains('provide')));
    expect(
      entries.where((entry) => entry.state == ExampleOperationState.waiting),
      hasLength(4),
    );
    expect(entries.last.operation, 'bitswapStats');
    expect(entries.last.state, ExampleOperationState.passed);
  });
}

final class _RecordingOperations implements ExampleNodeOperations {
  _RecordingOperations({required this.ready});

  final bool ready;
  final List<String> calls = [];

  @override
  Future<IpfsAddResult> addBytes(List<int> bytes) async {
    calls.add('add');
    return IpfsAddResult(cid: 'bafk-private-test', bytes: bytes.length);
  }

  @override
  Future<List<int>> getBlock(String cid) async {
    calls.add('get');
    return [1, 2, 3];
  }

  @override
  Future<void> pin(String cid) async => calls.add('pin');

  @override
  Future<List<IpfsPinInfo>> listPins() async {
    calls.add('listPins');
    return const [];
  }

  @override
  Future<bool> networkReady() async {
    calls.add('networkReady');
    return ready;
  }

  @override
  Future<void> provide(String cid) async => calls.add('provide');

  @override
  Future<List<IpfsPeerInfo>> findProviders(String cid) async {
    calls.add('findProviders');
    return const [];
  }

  @override
  Future<String> publishName(String cid) async {
    calls.add('publishName');
    return '/ipns/12D3Test';
  }

  @override
  Future<String> resolveName(String name) async {
    calls.add('resolveName');
    return '/ipfs/bafk-private-test';
  }

  @override
  Future<IpfsBitswapStats> bitswapStats() async {
    calls.add('bitswapStats');
    return const IpfsBitswapStats(
      blocksSent: 0,
      blocksReceived: 0,
      dataSent: 0,
      dataReceived: 0,
      wantlist: 0,
      messagesSent: 0,
      messagesReceived: 0,
    );
  }
}
