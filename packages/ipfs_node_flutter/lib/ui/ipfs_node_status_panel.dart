import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// A read-only snapshot of one [IpfsNode]'s runtime status.
///
/// The widget is presentational: the owning screen loads the [status] and
/// calls [onRefresh] to reload it.
class IpfsNodeStatusPanel extends StatelessWidget {
  const IpfsNodeStatusPanel({
    super.key,
    required this.status,
    this.loading = false,
    this.error,
    this.onRefresh,
  });

  final NodeStatus? status;
  final bool loading;
  final Object? error;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = status?.lifecycle == NodeLifecycle.running;
    final (icon, color) = switch (error) {
      final Object? error when error != null => (
          Icons.error_outline,
          theme.colorScheme.error
        ),
      _ when running => (Icons.check_circle, Colors.green),
      _ => (Icons.circle_outlined, theme.colorScheme.outline),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (loading)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('节点状态', style: theme.textTheme.titleMedium),
                ),
                if (onRefresh != null)
                  IconButton(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    tooltip: '刷新',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (loading)
              const Text('正在启动节点…')
            else if (error != null)
              SelectableText(
                '错误：$error',
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (status == null)
              const Text('节点未启动')
            else ...[
              _StatusRow(label: '生命周期', value: status!.lifecycle.name),
              _StatusRow(label: 'Peer ID', value: status!.peerId ?? '—'),
              _StatusRow(
                label: '监听地址',
                value: '${status!.listenAddrs.length} 个',
              ),
              _StatusRow(
                label: '已连接 peers',
                value: '${status!.connectedPeers.length} 个',
              ),
              if (status!.bootstrapErrors.isNotEmpty)
                _StatusRow(
                  label: 'bootstrap 错误',
                  value: '${status!.bootstrapErrors.length} 个',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );
}
