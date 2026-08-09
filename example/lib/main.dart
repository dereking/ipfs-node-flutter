import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';
import 'package:ipfs_node_flutter_native/ipfs_node_flutter_native.dart';

const documentedCid =
    'bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244';
const documentedContent = 'Hello IPFS\n';

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
        home: const PublicIpfsCheckPage(),
      );
}

class PublicIpfsCheckPage extends StatefulWidget {
  const PublicIpfsCheckPage({super.key, this.autoStart = true});

  final bool autoStart;

  @override
  State<PublicIpfsCheckPage> createState() => _PublicIpfsCheckPageState();
}

class _PublicIpfsCheckPageState extends State<PublicIpfsCheckPage> {
  IpfsNode? _node;
  NodeStatus? _status;
  String _step = '等待启动';
  String? _content;
  Object? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) _runCheck();
  }

  Future<void> _runCheck() async {
    if (_running) return;
    setState(() {
      _running = true;
      _step = '连接公共 IPFS bootstrap peers';
      _content = null;
      _error = null;
      _status = null;
    });

    await _node?.dispose();
    final node = IpfsNode();
    _node = node;
    try {
      await node.start(NodeConfig.public());
      final status = await node.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _step = '通过 DHT / Bitswap 读取固定 CID';
      });

      final bytes = await node.getBlock(documentedCid);
      final content = utf8.decode(bytes);
      if (content != documentedContent) {
        throw StateError('CID 内容不匹配：$content');
      }
      debugPrint(
        'IPFS_PUBLIC_TEST_PASS peer=${status.peerId} '
        'connected=${status.connectedPeers.length} cid=$documentedCid',
      );
      if (!mounted) return;
      setState(() {
        _content = content;
        _step = '验证通过：已连接公网并取回内容';
      });
    } catch (error, stackTrace) {
      debugPrint('IPFS_PUBLIC_TEST_FAIL $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _error = error;
        _step = '验证失败';
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _node?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final passed = _content == documentedContent;
    return Scaffold(
      appBar: AppBar(title: const Text('macOS 公共 IPFS 节点验证')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_running)
                        const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          passed ? Icons.check_circle : Icons.info_outline,
                          color: passed ? Colors.green : null,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _step,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Value(label: 'Peer ID', value: _status?.peerId ?? '—'),
                  _Value(
                    label: '已连接 peers',
                    value: '${_status?.connectedPeers.length ?? 0}',
                  ),
                  const _Value(label: '测试 CID', value: documentedCid),
                  _Value(
                    label: '返回内容',
                    value: _content == null ? '—' : jsonEncode(_content),
                  ),
                  if (_error != null)
                    SelectableText(
                      '错误：$_error',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running ? null : _runCheck,
            icon: const Icon(Icons.refresh),
            label: const Text('重新验证'),
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SelectableText('$label：$value'),
      );
}
