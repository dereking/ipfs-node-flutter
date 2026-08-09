import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// Renders one [IpfsFeatureCheck] and drives its execution.
///
/// Every run creates an isolated [IpfsNode] so concurrent or repeated checks
/// never interfere with each other.
class IpfsFeatureCheckCard extends StatefulWidget {
  const IpfsFeatureCheckCard({super.key, required this.check});

  final IpfsFeatureCheck check;

  @override
  State<IpfsFeatureCheckCard> createState() => _IpfsFeatureCheckCardState();
}

enum _CardState { idle, running, passed, failed }

class _IpfsFeatureCheckCardState extends State<IpfsFeatureCheckCard> {
  bool _running = false;
  String? _summary;
  Object? _error;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _summary = null;
      _error = null;
    });
    final node = IpfsNode();
    try {
      final summary = await widget.check.run(node);
      if (mounted) setState(() => _summary = summary);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      try {
        await node.dispose();
      } catch (_) {
        // Disposal must never mask a check result.
      }
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _running
        ? _CardState.running
        : _error != null
            ? _CardState.failed
            : _summary != null
                ? _CardState.passed
                : _CardState.idle;
    final (icon, color) = switch (state) {
      _CardState.running => (Icons.hourglass_top, theme.colorScheme.primary),
      _CardState.failed => (Icons.error, theme.colorScheme.error),
      _CardState.passed => (Icons.check_circle, Colors.green),
      _CardState.idle => (Icons.help_outline, theme.colorScheme.outline),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.check.title,
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        widget.check.description,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_running)
              const LinearProgressIndicator()
            else ...[
              if (_summary != null)
                SelectableText(
                  '通过：$_summary',
                  style: TextStyle(color: Colors.green.shade700),
                ),
              if (_error != null)
                SelectableText(
                  '失败：$_error',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: _run,
                  icon: Icon(
                    _error != null || _summary != null
                        ? Icons.refresh
                        : Icons.play_arrow,
                  ),
                  label: Text(
                    _error != null || _summary != null ? '重试' : '运行',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
