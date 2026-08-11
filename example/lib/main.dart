import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'feature_checks.dart';
import 'complete_example_page.dart';
import 'platform_registration.dart' as platform;

export 'complete_example_page.dart';

void main() {
  platform.registerIpfsNodePlatform();
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
        home: const CompleteIpfsExamplePage(),
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
  NodeStatus? _displayStatus;
  Object? _displayError;
  bool _loading = false;
  bool _networkReady = false;
  String? _repositoryPath;
  NodeConfig? _nodeConfig;
  int _pinCount = 0;
  late final IpfsNodeController _featureController;
  int _pinListVersion = 0;
  String? _selectedCid;

  @override
  void initState() {
    super.initState();
    _featureController = IpfsNodeController();
    if (widget.autoStart) {
      _startSharedNode();
    }
  }

  Future<void> _startSharedNode() async {
    setState(() {
      _loading = true;
      _displayError = null;
    });
    try {
      final directory = await getApplicationSupportDirectory();
      final repository =
          Directory('${directory.path}${Platform.pathSeparator}ipfs-node');
      final config = NodeConfig.public(repositoryPath: repository.path);
      _nodeConfig = config;
      _repositoryPath = repository.path;
      await _featureController.start(config);
      final status = await _featureController.node.status();
      final ready = await _featureController.node.networkReady();
      final pins = await _featureController.node.listPins();
      if (!mounted) return;
      setState(() {
        _displayStatus = status;
        _networkReady = ready;
        _pinCount = pins.length;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _displayError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _verifyWithKubo(String cid) async {
    if (kIsWeb) throw UnsupportedError('Web 不支持本机 Kubo 验证');
    final providers = await Process.run('ipfs', ['routing', 'findprovs', cid]);
    if (providers.exitCode != 0) {
      throw ProcessException('ipfs', ['routing', 'findprovs', cid],
          '${providers.stderr}', providers.exitCode);
    }
    final content = await Process.run('ipfs', ['cat', cid]);
    if (content.exitCode != 0) {
      throw ProcessException(
          'ipfs', ['cat', cid], '${content.stderr}', content.exitCode);
    }
    return 'Provider 查询成功；Kubo 已取回 ${('${content.stdout}').length} 字符';
  }

  @override
  void dispose() {
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

  Widget _buildTestTab(BuildContext context) => _KeepAliveTab(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IpfsNodeStatusPanel(
                status: _displayStatus,
                loading: _loading,
                error: _displayError,
                onRefresh: _loading ? null : _startSharedNode,
              ),
              const SizedBox(height: 24),
              Text('常见功能测试', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: _featureController,
                builder: (context, _) => _featureController.running
                    ? const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('单实例模式已启用：请先停止共享节点，再运行隔离功能测试。'),
                        ),
                      )
                    : IpfsFeatureCheckList(checks: commonIpfsFeatureChecks),
              ),
            ],
          ),
        ),
      );

  Widget _buildFeatureTab(BuildContext context) => _KeepAliveTab(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IpfsNodeLifecyclePanel(
                controller: _featureController,
                config: _nodeConfig,
              ),
              const SizedBox(height: 12),
              IpfsPublicationStatusPanel(
                status: _displayStatus,
                networkReady: _networkReady,
                publicAddressReady:
                    _networkReady && _displayStatus?.relayReady != true,
                publicationSupported: !kIsWeb,
              ),
              const SizedBox(height: 12),
              IpfsRepositoryPanel(
                repositoryPath: _repositoryPath ?? '浏览器 IndexedDB',
                contentCount: null,
                pinCount: _pinCount,
              ),
              const SizedBox(height: 12),
              IpfsCidFetchPanel(
                controller: _featureController,
                initialCid: documentedCid,
              ),
              const SizedBox(height: 12),
              IpfsContentAddPanel(
                controller: _featureController,
                initialText: documentedContent,
                publicationSupported: !kIsWeb,
                onAdded: (result) => setState(() => _selectedCid = result.cid),
              ),
              const SizedBox(height: 12),
              IpfsCidPublicationPanel(
                controller: _featureController,
                initialCid: _selectedCid ?? documentedCid,
                publicationSupported: !kIsWeb,
              ),
              const SizedBox(height: 12),
              IpfsKuboVerifyPanel(
                initialCid: documentedCid,
                onVerify: kIsWeb ? null : _verifyWithKubo,
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
          ),
        ),
      );
}

/// Keeps a tab's subtree alive while it is not the visible TabBarView page so
/// in-flight operations and edited text survive tab switches and scrolling.
class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
