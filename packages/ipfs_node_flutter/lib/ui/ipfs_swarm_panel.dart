import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// Shows connected peers and allows dialing or disconnecting them.
class IpfsSwarmPanel extends StatefulWidget {
  const IpfsSwarmPanel({super.key, required this.controller});

  final IpfsNodeController controller;

  @override
  State<IpfsSwarmPanel> createState() => _IpfsSwarmPanelState();
}

class _IpfsSwarmPanelState extends State<IpfsSwarmPanel> {
  late final TextEditingController _connectController = TextEditingController();
  List<IpfsPeerInfo>? _peers;
  bool _loading = false;
  bool _connecting = false;
  Object? _error;
  String? _summary;

  @override
  void initState() {
    super.initState();
    _loading = true;
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final peers = await widget.controller.node.swarmPeers();
      if (!mounted) return;
      setState(() {
        _peers = peers;
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

  Future<void> _connect() async {
    final multiaddr = _connectController.text.trim();
    if (multiaddr.isEmpty || _connecting) return;
    setState(() {
      _connecting = true;
      _summary = null;
      _error = null;
    });
    try {
      await widget.controller.node.swarmConnect(multiaddr);
      if (!mounted) return;
      setState(() => _summary = '已连接：$multiaddr');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect(IpfsPeerInfo peer) async {
    try {
      await widget.controller.node.swarmDisconnect(peer.id);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
    await _reload();
  }

  @override
  void dispose() {
    _connectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peers = _peers;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Swarm 连接', style: theme.textTheme.titleMedium),
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
                    controller: _connectController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '/ip4/1.2.3.4/tcp/4001/p2p/<peer>',
                    ),
                    onSubmitted: (_) => _connect(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _connecting ? null : _connect,
                  icon: const Icon(Icons.link),
                  label: const Text('连接'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_summary != null) SelectableText(_summary!),
            if (_error != null)
              SelectableText(
                '失败：$_error',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else if (peers == null || peers.isEmpty)
              const Text('暂无连接 peers')
            else
              for (final peer in peers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.dns, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: SelectableText(peer.id)),
                      IconButton(
                        onPressed: () => _disconnect(peer),
                        icon: const Icon(Icons.link_off),
                        tooltip: '断开',
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
