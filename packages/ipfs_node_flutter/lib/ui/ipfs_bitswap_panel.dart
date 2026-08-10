import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// Shows the node's current bitswap counters.
class IpfsBitswapPanel extends StatefulWidget {
  const IpfsBitswapPanel({super.key, required this.controller});

  final IpfsNodeController controller;

  @override
  State<IpfsBitswapPanel> createState() => _IpfsBitswapPanelState();
}

class _IpfsBitswapPanelState extends State<IpfsBitswapPanel> {
  IpfsBitswapStats? _stats;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loading = true;
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final stats = await widget.controller.node.bitswapStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Bitswap 统计', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  onPressed: _loading ? null : _reload,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              SelectableText(
                '加载失败：$_error',
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (stats != null) ...[
              _StatRow(label: '发送块', value: '${stats.blocksSent}'),
              _StatRow(label: '发送数据', value: _formatBytes(stats.dataSent)),
              _StatRow(label: '收到块', value: '${stats.blocksReceived}'),
              _StatRow(label: '收到数据', value: _formatBytes(stats.dataReceived)),
              _StatRow(label: 'Wantlist', value: '${stats.wantlist}'),
              _StatRow(label: '发送消息', value: '${stats.messagesSent}'),
              _StatRow(label: '收到消息', value: '${stats.messagesReceived}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}
