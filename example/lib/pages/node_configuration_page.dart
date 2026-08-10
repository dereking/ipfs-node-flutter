import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ipfs_node_example/example_node_configuration.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

class NodeConfigurationPage extends StatefulWidget {
  const NodeConfigurationPage({
    super.key,
    required this.controller,
    required this.applicationSupportPath,
    required this.onStart,
  });

  final IpfsNodeController controller;
  final String applicationSupportPath;
  final Future<void> Function(ExampleNodeConfiguration configuration) onStart;

  @override
  State<NodeConfigurationPage> createState() => _NodeConfigurationPageState();
}

class _NodeConfigurationPageState extends State<NodeConfigurationPage> {
  ExampleNetworkMode _mode = ExampleNetworkMode.public;
  late final TextEditingController _key;
  final _bootstrap = TextEditingController();
  final _relays = TextEditingController();
  final _allowed = TextEditingController();
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(
      text: ExampleNodeConfiguration.generateSwarmKeyHex(Random.secure()),
    );
  }

  @override
  void dispose() {
    _key.dispose();
    _bootstrap.dispose();
    _relays.dispose();
    _allowed.dispose();
    super.dispose();
  }

  List<String> _lines(TextEditingController controller) => controller.text
      .split('\n')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  Future<void> _start() async {
    try {
      final configuration = _mode == ExampleNetworkMode.public
          ? ExampleNodeConfiguration.public(bootstrapPeers: _lines(_bootstrap))
          : ExampleNodeConfiguration.private(
              swarmKeyHex: _key.text.trim(),
              bootstrapPeers: _lines(_bootstrap),
              relayPeers: _lines(_relays),
              allowedPeerIds: _lines(_allowed).toSet(),
            );
      configuration.build(widget.applicationSupportPath);
      setState(() => _validationError = null);
      await widget.onStart(configuration);
    } on FormatException catch (error) {
      setState(() => _validationError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('节点配置', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          SegmentedButton<ExampleNetworkMode>(
            segments: const [
              ButtonSegment(
                value: ExampleNetworkMode.public,
                label: Text('公共网络'),
                icon: Icon(Icons.public),
              ),
              ButtonSegment(
                value: ExampleNetworkMode.private,
                label: Text('私有网络'),
                icon: Icon(Icons.lock),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: widget.controller.running
                ? null
                : (value) => setState(() => _mode = value.single),
          ),
          const SizedBox(height: 12),
          SelectableText('应用数据目录：${widget.applicationSupportPath}'),
          if (_mode == ExampleNetworkMode.private) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              decoration: const InputDecoration(
                labelText: 'Swarm Key（64 位十六进制）',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _key.text = ExampleNodeConfiguration.generateSwarmKeyHex(
                    Random.secure(),
                  );
                }),
                icon: const Icon(Icons.key),
                label: const Text('生成密钥'),
              ),
            ),
          ],
          TextField(
            controller: _bootstrap,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Bootstrap 节点（每行一个）',
              border: OutlineInputBorder(),
            ),
          ),
          if (_mode == ExampleNetworkMode.private)
            ExpansionTile(
              title: const Text('高级私有网络参数'),
              children: [
                TextField(
                  controller: _relays,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Relay 节点（每行一个）',
                  ),
                ),
                TextField(
                  controller: _allowed,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '允许的 Peer ID（每行一个，可选）',
                  ),
                ),
              ],
            ),
          if (_validationError != null)
            Text(_validationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.controller.running)
                FilledButton.tonalIcon(
                  onPressed:
                      widget.controller.loading ? null : widget.controller.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止节点'),
                )
              else
                FilledButton.icon(
                  onPressed: widget.controller.loading ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('启动节点'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          IpfsNodeStatusPanel(
            status: widget.controller.status,
            loading: widget.controller.loading,
            error: widget.controller.error,
            onRefresh:
                widget.controller.running ? widget.controller.refresh : null,
          ),
        ],
      );
}
