import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// Publishes content under an IPNS name and resolves IPNS names.
class IpfsIpnsPanel extends StatefulWidget {
  const IpfsIpnsPanel({
    super.key,
    required this.controller,
    this.initialCid,
  });

  final IpfsNodeController controller;
  final String? initialCid;

  @override
  State<IpfsIpnsPanel> createState() => _IpfsIpnsPanelState();
}

class _IpfsIpnsPanelState extends State<IpfsIpnsPanel> {
  late final TextEditingController _cidController =
      TextEditingController(text: widget.initialCid ?? '');
  late final TextEditingController _nameController = TextEditingController();
  List<IpfsKeyInfo>? _keys;
  bool _publishing = false;
  bool _resolving = false;
  Object? _error;
  String? _published;
  String? _resolved;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    try {
      final keys = await widget.controller.node.listKeys();
      if (!mounted) return;
      setState(() => _keys = keys);
    } catch (_) {
      // Key listing is best-effort; publishing will surface real errors.
    }
  }

  Future<void> _publish() async {
    final cid = _cidController.text.trim();
    if (cid.isEmpty || _publishing) return;
    setState(() {
      _publishing = true;
      _error = null;
      _published = null;
    });
    try {
      final name = await widget.controller.node.publishName(cid);
      if (!mounted) return;
      setState(() {
        _published = name;
        _nameController.text = '/ipns/$name';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _resolve() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _resolving) return;
    setState(() {
      _resolving = true;
      _error = null;
      _resolved = null;
    });
    try {
      final path = await widget.controller.node.resolveName(name);
      if (!mounted) return;
      setState(() => _resolved = path);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  void dispose() {
    _cidController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = _keys;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('IPNS', style: theme.textTheme.titleMedium),
            if (keys != null && keys.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'self：${keys.first.peerId}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cidController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '内容 CID',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _publishing ? null : _publish,
                  icon: const Icon(Icons.publish),
                  label: const Text('发布'),
                ),
              ],
            ),
            if (_published != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText('已发布：$_published'),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'IPNS 名称',
                      hintText: '/ipns/<peer>',
                    ),
                    onSubmitted: (_) => _resolve(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _resolving ? null : _resolve,
                  icon: const Icon(Icons.search),
                  label: const Text('解析'),
                ),
              ],
            ),
            if (_resolved != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText('解析结果：$_resolved'),
              ),
            const SizedBox(height: 8),
            if (_loadingAny)
              const LinearProgressIndicator()
            else if (_error != null)
              SelectableText(
                '失败：$_error',
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  bool get _loadingAny => _publishing || _resolving;
}
