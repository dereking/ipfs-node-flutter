import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

class IpfsCidPublicationPanel extends StatefulWidget {
  const IpfsCidPublicationPanel({
    super.key,
    required this.controller,
    this.initialCid,
    this.publicationSupported = true,
  });

  final IpfsNodeController controller;
  final String? initialCid;
  final bool publicationSupported;

  @override
  State<IpfsCidPublicationPanel> createState() =>
      _IpfsCidPublicationPanelState();
}

class _IpfsCidPublicationPanelState extends State<IpfsCidPublicationPanel> {
  late final TextEditingController _cid =
      TextEditingController(text: widget.initialCid);
  String? _result;
  bool _loading = false;

  Future<void> _provide() async {
    if (!widget.publicationSupported || _cid.text.isEmpty) return;
    await _run(() async {
      await widget.controller.node.provide(_cid.text);
      return '发布成功：${_cid.text}';
    });
  }

  Future<void> _providers() => _run(() async {
        final providers = await widget.controller.node.findProviders(_cid.text);
        return providers.isEmpty
            ? '未找到 Provider'
            : 'Provider：${providers.map((peer) => peer.id).join(', ')}';
      });

  Future<void> _run(Future<String> Function() action) async {
    if (_loading || _cid.text.isEmpty) return;
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final result = await action();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _result = '失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _cid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CID 发布状态', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
                controller: _cid,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: 'CID')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton(
                  onPressed: _loading || !widget.publicationSupported
                      ? null
                      : _provide,
                  child: const Text('重新发布')),
              OutlinedButton(
                  onPressed: _loading ? null : _providers,
                  child: const Text('查询 Provider')),
            ]),
            if (!widget.publicationSupported) const Text('当前平台不支持公网发布'),
            if (_loading) const LinearProgressIndicator(),
            if (_result != null) SelectableText(_result!),
          ]),
        ),
      );
}
