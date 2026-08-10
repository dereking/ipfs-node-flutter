import 'package:flutter/material.dart';

import 'ipfs_node_controller.dart';

/// Pins or unpins a content root by CID on the shared node.
class IpfsPinPanel extends StatefulWidget {
  const IpfsPinPanel({
    super.key,
    required this.controller,
    this.initialCid,
    this.onChanged,
  });

  final IpfsNodeController controller;
  final String? initialCid;

  /// Invoked after a successful pin or unpin so lists can refresh.
  final VoidCallback? onChanged;

  @override
  State<IpfsPinPanel> createState() => _IpfsPinPanelState();
}

class _IpfsPinPanelState extends State<IpfsPinPanel> {
  late final TextEditingController _cidController =
      TextEditingController(text: widget.initialCid ?? '');
  bool _loading = false;
  String? _summary;
  Object? _error;

  Future<void> _pin() async {
    final cid = _cidController.text.trim();
    if (cid.isEmpty || _loading) return;
    await _run(() => widget.controller.node.pin(cid), '已固定：$cid');
  }

  Future<void> _unpin() async {
    final cid = _cidController.text.trim();
    if (cid.isEmpty || _loading) return;
    await _run(() => widget.controller.node.unpin(cid), '已取消固定：$cid');
  }

  Future<void> _run(Future<void> Function() action, String summary) async {
    setState(() {
      _loading = true;
      _summary = null;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() => _summary = summary);
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _cidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('固定内容', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _cidController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'CID',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _unpin,
                  icon: const Icon(Icons.push_pin_outlined),
                  label: const Text('取消固定'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _pin,
                  icon: const Icon(Icons.push_pin),
                  label: const Text('固定'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else ...[
              if (_summary != null) SelectableText(_summary!),
              if (_error != null)
                SelectableText(
                  '失败：$_error',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
