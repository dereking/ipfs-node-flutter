import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:ipfs_node_flutter_native/ipfs_node_flutter_native.dart';

import 'feature_checks.dart';

void main() {
  IpfsNodeFlutterNative.registerWith();
  runApp(const IpfsNodeExampleApp());
}

class IpfsNodeExampleApp extends StatelessWidget {
  const IpfsNodeExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'IPFS Node macOS Example',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        home: const IpfsFeatureLabPage(),
      );
}

/// A two-tab dashboard: common IPFS feature tests and everyday node usage.
class IpfsFeatureLabPage extends StatefulWidget {
  const IpfsFeatureLabPage({super.key, this.autoStart = true});

  final bool autoStart;

  @override
  State<IpfsFeatureLabPage> createState() => _IpfsFeatureLabPageState();
}

class _IpfsFeatureLabPageState extends State<IpfsFeatureLabPage> {
  IpfsNode? _displayNode;
  NodeStatus? _displayStatus;
  Object? _displayError;
  bool _loading = false;
  late final IpfsNodeController _featureController;
  int _pinListVersion = 0;

  @override
  void initState() {
    super.initState();
    _featureController = IpfsNodeController();
    if (widget.autoStart) {
      _refreshDisplayNode();
      _featureController.start(NodeConfig.public());
    }
  }

  Future<void> _refreshDisplayNode() async {
    setState(() {
      _loading = true;
      _displayError = null;
    });
    await _displayNode?.dispose();
    final node = IpfsNode();
    _displayNode = node;
    try {
      await node.start(NodeConfig.public());
      final status = await node.status();
      if (!mounted) return;
      setState(() => _displayStatus = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _displayError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _displayNode?.dispose();
    _featureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('IPFS 功能验证'),
            bottom: const TabBar(
              tabs: [
                Tab(text: '功能测试'),
                Tab(text: '常用功能'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildTestTab(context),
              _buildFeatureTab(context),
            ],
          ),
        ),
      );

  Widget _buildTestTab(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IpfsNodeStatusPanel(
            status: _displayStatus,
            loading: _loading,
            error: _displayError,
            onRefresh: _loading ? null : _refreshDisplayNode,
          ),
          const SizedBox(height: 24),
          Text('常见功能测试', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          IpfsFeatureCheckList(checks: commonIpfsFeatureChecks),
        ],
      );

  Widget _buildFeatureTab(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IpfsNodeLifecyclePanel(controller: _featureController),
          const SizedBox(height: 12),
          IpfsCidFetchPanel(
            controller: _featureController,
            initialCid: documentedCid,
          ),
          const SizedBox(height: 12),
          IpfsContentAddPanel(
            controller: _featureController,
            initialText: documentedContent,
          ),
          const SizedBox(height: 12),
          IpfsPinPanel(
            controller: _featureController,
            onChanged: () => setState(() => _pinListVersion++),
          ),
          const SizedBox(height: 12),
          IpfsPinListPanel(
            key: ValueKey(_pinListVersion),
            controller: _featureController,
          ),
          const SizedBox(height: 12),
          IpfsSwarmPanel(controller: _featureController),
          const SizedBox(height: 12),
          IpfsBootstrapPanel(controller: _featureController),
          const SizedBox(height: 12),
          IpfsBitswapPanel(controller: _featureController),
          const SizedBox(height: 12),
          IpfsDhtPanel(
            controller: _featureController,
            initialCid: documentedCid,
          ),
          const SizedBox(height: 12),
          IpfsIpnsPanel(
            controller: _featureController,
            initialCid: documentedCid,
          ),
        ],
      );
}
