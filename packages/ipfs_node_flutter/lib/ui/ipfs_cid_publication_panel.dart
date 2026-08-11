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
      final status = await widget.controller.node.publicationStatus(_cid.text);
      return '严格发布已确认\n${_describe(status)}';
    });
  }

  Future<void> _schedule() async {
    if (!widget.publicationSupported || _cid.text.isEmpty) return;
    await _run(() async {
      await widget.controller.node.startProviding(_cid.text);
      final status = await widget.controller.node.publicationStatus(_cid.text);
      return '已加入持久化发布队列\n${_describe(status)}';
    });
  }

  Future<void> _status() => _run(() async {
        final status =
            await widget.controller.node.publicationStatus(_cid.text);
        return _describe(status);
      });

  Future<void> _list() => _run(() async {
        final statuses = await widget.controller.node.listPublicationStatuses();
        if (statuses.isEmpty) return '发布队列为空';
        return statuses.map(_describe).join('\n\n');
      }, requiresCid: false);

  String _describe(IpfsPublicationStatus status) {
    final retry = status.nextRetry?.toLocal().toIso8601String();
    final published = status.lastPublished?.toLocal().toIso8601String();
    return '${status.cid}\n状态=${status.state.name}，确认='
        '${status.confirmedPeers}/${status.requiredConfirmations}，写入='
        '${status.writeSuccesses}/${status.targetPeers}，尝试='
        '${status.attemptCount}'
        '${published == null ? '' : '，最近成功=$published'}'
        '${retry == null ? '' : '，下次重试=$retry'}'
        '${status.publishError == null ? '' : '\n错误=${status.publishError}'}';
  }

  Future<void> _providers() => _run(() async {
        final providers = await widget.controller.node.findProviders(_cid.text);
        return providers.isEmpty
            ? '未找到 Provider'
            : 'Provider：${providers.map((peer) => peer.id).join(', ')}';
      });

  Future<void> _run(
    Future<String> Function() action, {
    bool requiresCid = true,
  }) async {
    if (_loading || (requiresCid && _cid.text.isEmpty)) return;
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
                  child: const Text('严格发布并确认')),
              OutlinedButton(
                  onPressed: _loading || !widget.publicationSupported
                      ? null
                      : _schedule,
                  child: const Text('加入后台发布队列')),
              OutlinedButton(
                  onPressed:
                      _loading || !widget.publicationSupported ? null : _status,
                  child: const Text('查询本地发布状态')),
              OutlinedButton(
                  onPressed:
                      _loading || !widget.publicationSupported ? null : _list,
                  child: const Text('查看发布队列')),
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
