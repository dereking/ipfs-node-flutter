import 'dart:convert';
import 'dart:typed_data';

import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

abstract interface class ExampleNodeOperations {
  Future<IpfsAddResult> addBytes(List<int> bytes);
  Future<List<int>> getBlock(String cid);
  Future<void> pin(String cid);
  Future<List<IpfsPinInfo>> listPins();
  Future<bool> networkReady();
  Future<void> provide(String cid);
  Future<List<IpfsPeerInfo>> findProviders(String cid);
  Future<String> publishName(String cid);
  Future<String> resolveName(String name);
  Future<IpfsBitswapStats> bitswapStats();
}

final class IpfsNodeOperations implements ExampleNodeOperations {
  const IpfsNodeOperations(this.node);

  final IpfsNode node;

  @override
  Future<IpfsAddResult> addBytes(List<int> bytes) =>
      node.addBytes(Uint8List.fromList(bytes));
  @override
  Future<List<int>> getBlock(String cid) => node.getBlock(cid);
  @override
  Future<void> pin(String cid) => node.pin(cid);
  @override
  Future<List<IpfsPinInfo>> listPins() => node.listPins();
  @override
  Future<bool> networkReady() => node.networkReady();
  @override
  Future<void> provide(String cid) => node.provide(cid);
  @override
  Future<List<IpfsPeerInfo>> findProviders(String cid) =>
      node.findProviders(cid);
  @override
  Future<String> publishName(String cid) => node.publishName(cid);
  @override
  Future<String> resolveName(String name) => node.resolveName(name);
  @override
  Future<IpfsBitswapStats> bitswapStats() => node.bitswapStats();
}

enum ExampleOperationState { running, passed, waiting, failed }

final class ExampleOperationLogEntry {
  const ExampleOperationLogEntry({
    required this.operation,
    required this.state,
    required this.elapsed,
    this.details,
  });

  final String operation;
  final ExampleOperationState state;
  final Duration elapsed;
  final String? details;
}

final class ExampleOperationRunner {
  ExampleOperationRunner({this.onChanged});

  final void Function(List<ExampleOperationLogEntry> entries)? onChanged;
  final List<ExampleOperationLogEntry> _entries = [];

  List<ExampleOperationLogEntry> get entries => List.unmodifiable(_entries);

  Future<List<ExampleOperationLogEntry>> run(
    ExampleNodeOperations node, {
    String content = 'IPFS Example 全功能演示\n',
  }) async {
    _entries.clear();
    _notify();

    final added = await _perform(
      'add',
      () => node.addBytes(utf8.encode(content)),
      (result) => result.cid,
    );
    final cid = added?.cid;

    if (cid == null) {
      _waiting('get', '本地添加失败，缺少 CID');
      _waiting('pin', '本地添加失败，缺少 CID');
      _waiting('listPins', 'Pin 步骤未完成');
    } else {
      await _perform(
          'get', () => node.getBlock(cid), (bytes) => '${bytes.length} bytes');
      await _perform('pin', () => node.pin(cid), (_) => cid);
      await _perform(
          'listPins', node.listPins, (pins) => '${pins.length} pins');
    }

    var ready = false;
    try {
      ready = await node.networkReady();
    } catch (error) {
      _waiting('provide', '网络状态不可用：$error');
    }

    if (cid == null) {
      _waiting('provide', '缺少 CID');
      _waiting('findProviders', '缺少 CID');
      _waiting('publishName', '缺少 CID');
      _waiting('resolveName', '缺少 IPNS 名称');
    } else if (!ready) {
      _waiting('provide', '等待 DHT/Relay 或私有 Peer 就绪');
      _waiting('findProviders', 'Provider routing 尚未就绪');
      _waiting('publishName', 'Provider routing 尚未就绪');
      _waiting('resolveName', 'IPNS 尚未发布');
    } else {
      await _perform('provide', () => node.provide(cid), (_) => cid);
      await _perform(
        'findProviders',
        () => node.findProviders(cid),
        (providers) => '${providers.length} providers',
      );
      final name = await _perform(
          'publishName', () => node.publishName(cid), (value) => value);
      if (name == null) {
        _waiting('resolveName', 'IPNS 发布失败');
      } else {
        await _perform(
            'resolveName', () => node.resolveName(name), (value) => value);
      }
    }

    await _perform(
      'bitswapStats',
      node.bitswapStats,
      (stats) => 'received=${stats.blocksReceived}, sent=${stats.blocksSent}',
    );
    return entries;
  }

  Future<T?> _perform<T>(
    String operation,
    Future<T> Function() action,
    String Function(T value) describe,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final value = await action();
      stopwatch.stop();
      _entries.add(ExampleOperationLogEntry(
        operation: operation,
        state: ExampleOperationState.passed,
        elapsed: stopwatch.elapsed,
        details: describe(value),
      ));
      _notify();
      return value;
    } catch (error) {
      stopwatch.stop();
      _entries.add(ExampleOperationLogEntry(
        operation: operation,
        state: ExampleOperationState.failed,
        elapsed: stopwatch.elapsed,
        details: '$error',
      ));
      _notify();
      return null;
    }
  }

  void _waiting(String operation, String details) {
    if (_entries.any((entry) => entry.operation == operation)) return;
    _entries.add(ExampleOperationLogEntry(
      operation: operation,
      state: ExampleOperationState.waiting,
      elapsed: Duration.zero,
      details: details,
    ));
    _notify();
  }

  void _notify() => onChanged?.call(entries);
}
