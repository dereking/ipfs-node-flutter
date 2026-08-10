import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

class IpfsFindPeerPanel extends StatefulWidget {
  const IpfsFindPeerPanel({super.key, required this.controller});

  final IpfsNodeController controller;

  @override
  State<IpfsFindPeerPanel> createState() => _IpfsFindPeerPanelState();
}

class _IpfsFindPeerPanelState extends State<IpfsFindPeerPanel> {
  final _peerId = TextEditingController();
  bool _loading = false;
  String? _result;

  @override
  void dispose() {
    _peerId.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final peerId = _peerId.text.trim();
    if (peerId.isEmpty) return;
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final peer = await widget.controller.node.findPeer(peerId);
      if (!mounted) return;
      setState(() => _result = '${peer.id}\n${peer.addrs.join('\n')}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _result = '查找失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Peer 路由查询', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _peerId,
                decoration: const InputDecoration(labelText: 'Peer ID'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _loading ? null : _find,
                  child: Text(_loading ? '查找中…' : '查找 Peer'),
                ),
              ),
              if (_result != null) SelectableText(_result!),
            ],
          ),
        ),
      );
}
