import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// Queries the DHT for providers of a content root.
class IpfsDhtPanel extends StatefulWidget {
  const IpfsDhtPanel({
    super.key,
    required this.controller,
    this.initialCid,
  });

  final IpfsNodeController controller;
  final String? initialCid;

  @override
  State<IpfsDhtPanel> createState() => _IpfsDhtPanelState();
}

class _IpfsDhtPanelState extends State<IpfsDhtPanel> {
  late final TextEditingController _cidController =
      TextEditingController(text: widget.initialCid ?? '');
  List<IpfsPeerInfo>? _providers;
  bool _loading = false;
  Object? _error;

  Future<void> _query() async {
    final cid = _cidController.text.trim();
    if (cid.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _providers = null;
      _error = null;
    });
    try {
      final providers = await widget.controller.node.findProviders(cid);
      if (!mounted) return;
      setState(() => _providers = providers);
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
    final providers = _providers;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DHT Providers', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cidController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'CID',
                    ),
                    onSubmitted: (_) => _query(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _query,
                  icon: const Icon(Icons.search),
                  label: const Text('查询'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              SelectableText(
                '失败：$_error',
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (providers == null)
              const Text('输入 CID 后查询 provider 节点')
            else if (providers.isEmpty)
              const Text('未找到 provider')
            else
              for (final provider in providers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.dns, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: SelectableText(provider.id)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
