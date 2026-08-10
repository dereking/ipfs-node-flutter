import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'example_node_configuration.dart';
import 'example_operation_runner.dart';
import 'pages/content_repository_page.dart';
import 'pages/ipns_diagnostics_page.dart';
import 'pages/network_routing_page.dart';
import 'pages/node_configuration_page.dart';

class CompleteIpfsExamplePage extends StatefulWidget {
  const CompleteIpfsExamplePage({
    super.key,
    this.autoStart = true,
    this.applicationSupportPath,
  });

  final bool autoStart;
  final String? applicationSupportPath;

  @override
  State<CompleteIpfsExamplePage> createState() =>
      _CompleteIpfsExamplePageState();
}

class _CompleteIpfsExamplePageState extends State<CompleteIpfsExamplePage> {
  late final IpfsNodeController _controller;
  late final ExampleOperationRunner _runner;
  String? _supportPath;
  ExampleNodeConfiguration _configuration =
      const ExampleNodeConfiguration.public();
  CapabilitySet _capabilities = const CapabilitySet.empty();
  NodeStatus? _status;
  bool _networkReady = false;
  bool _runningAll = false;
  int _pinCount = 0;
  int _page = 0;
  Timer? _refreshTimer;
  List<ExampleOperationLogEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _controller = IpfsNodeController();
    _runner = ExampleOperationRunner(onChanged: (entries) {
      if (mounted) setState(() => _entries = entries);
    });
    _initialize();
  }

  Future<void> _initialize() async {
    final supportPath = widget.applicationSupportPath ??
        (kIsWeb
            ? 'browser-indexeddb'
            : (await getApplicationSupportDirectory()).path);
    if (!mounted) return;
    setState(() => _supportPath = supportPath);
    if (widget.autoStart) {
      await _start(const ExampleNodeConfiguration.public());
    }
  }

  Future<void> _start(ExampleNodeConfiguration configuration) async {
    final supportPath = _supportPath;
    if (supportPath == null) return;
    _refreshTimer?.cancel();
    if (_controller.running) await _controller.stop();
    _clearDiagnostics();
    _configuration = configuration;
    await _controller.start(configuration.build(supportPath));
    await _refresh();
    if (_controller.running) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_refresh()),
      );
    }
  }

  void _clearDiagnostics() {
    if (!mounted) return;
    setState(() {
      _status = null;
      _capabilities = const CapabilitySet.empty();
      _networkReady = false;
      _pinCount = 0;
      _entries = const [];
    });
  }

  Future<void> _refresh() async {
    if (!_controller.running) {
      if (mounted) setState(() => _status = _controller.status);
      return;
    }
    NodeStatus? status;
    CapabilitySet? capabilities;
    bool? ready;
    int? pins;
    try {
      status = await _controller.node.status();
    } catch (_) {}
    try {
      capabilities = await _controller.node.capabilities();
    } catch (_) {}
    try {
      ready = await _controller.node.networkReady();
    } catch (_) {}
    try {
      pins = (await _controller.node.listPins()).length;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (status != null) _status = status;
      if (capabilities != null) _capabilities = capabilities;
      if (ready != null) _networkReady = ready;
      if (pins != null) _pinCount = pins;
    });
  }

  Future<void> _runAll() async {
    if (!_controller.running || _runningAll) return;
    setState(() => _runningAll = true);
    try {
      await _runner.run(IpfsNodeOperations(_controller.node));
      await _refresh();
    } finally {
      if (mounted) setState(() => _runningAll = false);
    }
  }

  List<IpfsOperationLogItem> get _logItems => _entries
      .map((entry) => IpfsOperationLogItem(
            operation: entry.operation,
            state: switch (entry.state) {
              ExampleOperationState.running => IpfsOperationLogState.running,
              ExampleOperationState.passed => IpfsOperationLogState.passed,
              ExampleOperationState.waiting => IpfsOperationLogState.waiting,
              ExampleOperationState.failed => IpfsOperationLogState.failed,
            },
            elapsed: entry.elapsed,
            details: entry.details,
          ))
      .toList(growable: false);

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supportPath = _supportPath;
    final repositoryPath = supportPath == null
        ? '正在解析应用数据目录…'
        : _configuration.repositoryPath(supportPath);
    final providerRouting = _capabilities.contains(Capability.providerRouting);
    final pages = <Widget>[
      NodeConfigurationPage(
        controller: _controller,
        applicationSupportPath: supportPath ?? '正在解析…',
        onStart: _start,
      ),
      ContentRepositoryPage(
        controller: _controller,
        repositoryPath: repositoryPath,
        pinCount: _pinCount,
        publicationSupported: providerRouting,
      ),
      NetworkRoutingPage(
        controller: _controller,
        status: _status,
        networkReady: _networkReady,
        publicationSupported: providerRouting,
      ),
      IpnsDiagnosticsPage(
        controller: _controller,
        capabilities: _capabilities,
        temporarilyUnavailable: {
          if (providerRouting && !_networkReady) Capability.providerRouting,
          if (_capabilities.contains(Capability.publicPublication) &&
              !_networkReady)
            Capability.publicPublication,
        },
        logItems: _logItems,
        runningAll: _runningAll,
        onRunAll: _controller.running ? _runAll : null,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('IPFS SDK 完整示例')),
      body: IndexedStack(index: _page, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (value) => setState(() => _page = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.settings), label: '节点配置'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: '内容与仓库'),
          NavigationDestination(icon: Icon(Icons.hub), label: '网络与路由'),
          NavigationDestination(icon: Icon(Icons.badge), label: 'IPNS 与诊断'),
        ],
      ),
    );
  }
}
