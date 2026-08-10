import 'package:flutter/material.dart';

import 'ipfs_node_controller.dart';

/// Shows the configured bootstrap peers and allows adding or removing them.
class IpfsBootstrapPanel extends StatefulWidget {
  const IpfsBootstrapPanel({super.key, required this.controller});

  final IpfsNodeController controller;

  @override
  State<IpfsBootstrapPanel> createState() => _IpfsBootstrapPanelState();
}

class _IpfsBootstrapPanelState extends State<IpfsBootstrapPanel> {
  late final TextEditingController _addController = TextEditingController();
  List<String>? _bootstraps;
  bool _loading = false;
  bool _adding = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loading = true;
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final bootstraps = await widget.controller.node.bootstrapList();
      if (!mounted) return;
      setState(() {
        _bootstraps = bootstraps;
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

  Future<void> _add() async {
    final multiaddr = _addController.text.trim();
    if (multiaddr.isEmpty || _adding) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await widget.controller.node.bootstrapAdd(multiaddr);
      _addController.clear();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
    await _reload();
  }

  Future<void> _remove(String multiaddr) async {
    try {
      await widget.controller.node.bootstrapRemove(multiaddr);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
    await _reload();
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bootstraps = _bootstraps;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child:
                      Text('Bootstrap 节点', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  onPressed: _loading ? null : _reload,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '/dnsaddr/bootstrap.libp2p.io/p2p/<peer>',
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _adding ? null : _add,
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null)
              SelectableText(
                '失败：$_error',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else if (bootstraps == null || bootstraps.isEmpty)
              const Text('暂无 bootstrap 节点')
            else
              for (final multiaddr in bootstraps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.hub, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: SelectableText(multiaddr)),
                      IconButton(
                        onPressed: () => _remove(multiaddr),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '移除',
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
