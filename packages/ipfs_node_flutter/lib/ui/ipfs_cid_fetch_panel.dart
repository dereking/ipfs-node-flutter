import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'ipfs_node_controller.dart';

/// Fetches a raw IPFS block by CID through a shared [IpfsNodeController.node].
///
/// Content is rendered as UTF-8 text when it decodes cleanly and as base64
/// otherwise.
class IpfsCidFetchPanel extends StatefulWidget {
  const IpfsCidFetchPanel({
    super.key,
    required this.controller,
    this.initialCid,
  });

  final IpfsNodeController controller;
  final String? initialCid;

  @override
  State<IpfsCidFetchPanel> createState() => _IpfsCidFetchPanelState();
}

class _IpfsCidFetchPanelState extends State<IpfsCidFetchPanel> {
  late final TextEditingController _cidController =
      TextEditingController(text: widget.initialCid ?? '');
  bool _loading = false;
  Object? _error;
  String? _summary;

  Future<void> _fetch() async {
    final cid = _cidController.text.trim();
    if (cid.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _summary = null;
    });
    try {
      final bytes = await widget.controller.node.getBlock(cid);
      if (!mounted) return;
      setState(() => _summary = _render(bytes));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _render(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes);
      return '${bytes.length} 字节，内容：${jsonEncode(text)}';
    } on FormatException {
      return '${bytes.length} 字节（非 UTF-8）：${base64Encode(bytes)}';
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
            Text('按 CID 取回内容', style: theme.textTheme.titleMedium),
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
                    onSubmitted: (_) => _fetch(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _fetch,
                  icon: const Icon(Icons.download),
                  label: const Text('获取'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else ...[
              if (_summary != null)
                SelectableText('成功：$_summary'),
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
