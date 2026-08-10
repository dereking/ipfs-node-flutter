import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// Lists the locally pinned content roots and allows unpinning them.
class IpfsPinListPanel extends StatefulWidget {
  const IpfsPinListPanel({super.key, required this.controller});

  final IpfsNodeController controller;

  @override
  State<IpfsPinListPanel> createState() => _IpfsPinListPanelState();
}

class _IpfsPinListPanelState extends State<IpfsPinListPanel> {
  List<IpfsPinInfo>? _pins;
  bool _loading = false;
  Object? _error;
  String? _unpinning;

  @override
  void initState() {
    super.initState();
    _loading = true;
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final pins = await widget.controller.node.listPins();
      if (!mounted) return;
      setState(() {
        _pins = pins;
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

  Future<void> _unpin(IpfsPinInfo pin) async {
    if (_unpinning != null) return;
    setState(() => _unpinning = pin.cid);
    try {
      await widget.controller.node.unpin(pin.cid);
    } finally {
      if (mounted) setState(() => _unpinning = null);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pins = _pins;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('固定列表', style: theme.textTheme.titleMedium),
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
            else if (pins == null || pins.isEmpty)
              const Text('暂无固定内容')
            else
              for (final pin in pins)
                _PinTile(
                  pin: pin,
                  unpinning: _unpinning == pin.cid,
                  onUnpin: () => _unpin(pin),
                ),
          ],
        ),
      ),
    );
  }
}

class _PinTile extends StatelessWidget {
  const _PinTile({
    required this.pin,
    required this.unpinning,
    required this.onUnpin,
  });

  final IpfsPinInfo pin;
  final bool unpinning;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pinnedAt = pin.pinnedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.push_pin, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(pin.cid),
                if (pinnedAt != null)
                  Text(
                    '${pin.type.name} · ${pinnedAt.toLocal()}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: unpinning ? null : onUnpin,
            icon: unpinning
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            tooltip: '取消固定',
          ),
        ],
      ),
    );
  }
}
