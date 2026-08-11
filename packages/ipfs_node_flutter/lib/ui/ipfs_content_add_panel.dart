import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// Adds text content to the shared node and shows the resulting CID.
class IpfsContentAddPanel extends StatefulWidget {
  const IpfsContentAddPanel({
    super.key,
    required this.controller,
    this.initialText,
    this.publicationSupported = true,
    this.onAdded,
  });

  final IpfsNodeController controller;
  final String? initialText;
  final bool publicationSupported;
  final ValueChanged<IpfsAddResult>? onAdded;

  @override
  State<IpfsContentAddPanel> createState() => _IpfsContentAddPanelState();
}

class _IpfsContentAddPanelState extends State<IpfsContentAddPanel> {
  late final TextEditingController _textController =
      TextEditingController(text: widget.initialText ?? '');
  bool _loading = false;
  IpfsAddResult? _result;
  Object? _error;
  bool _published = false;

  Future<void> _add({required bool publish}) async {
    final text = _textController.text;
    if (text.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _result = null;
      _error = null;
      _published = false;
    });
    try {
      final result = publish
          ? await widget.controller.node.addAndProvide(utf8.encode(text))
          : await widget.controller.node.addText(text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _published = publish;
      });
      widget.onAdded?.call(result);
    } catch (error) {
      if (!mounted) return;
      IpfsAddResult? durableResult;
      setState(() {
        if (error is IpfsPublicationException) {
          _result = error.result;
          durableResult = error.result;
        }
        _error = error;
      });
      if (durableResult != null) widget.onAdded?.call(durableResult!);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyCid() async {
    final cid = _result?.cid;
    if (cid == null) return;
    await Clipboard.setData(ClipboardData(text: cid));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('CID 已复制')));
    }
  }

  @override
  void dispose() {
    _textController.dispose();
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
            Text('添加内容', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _textController,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入要添加到 IPFS 的文本',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _add(publish: false),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('本地添加'),
                ),
                FilledButton.icon(
                  onPressed: _loading || !widget.publicationSupported
                      ? null
                      : () => _add(publish: true),
                  icon: const Icon(Icons.public),
                  label: const Text('添加并发布'),
                ),
              ],
            ),
            if (!widget.publicationSupported)
              const Text('当前平台不支持公网发布；仍可本地添加和读取'),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else ...[
              if (_result != null) ...[
                SelectableText(
                  '${_published ? '已发布' : '已保存到本地'}：${_result!.cid}（${_result!.bytes} 字节）',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _copyCid,
                    icon: const Icon(Icons.copy),
                    label: const Text('复制 CID'),
                  ),
                ),
              ],
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
