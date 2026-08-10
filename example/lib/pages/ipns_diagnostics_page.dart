import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

class IpnsDiagnosticsPage extends StatelessWidget {
  const IpnsDiagnosticsPage({
    super.key,
    required this.controller,
    required this.capabilities,
    required this.temporarilyUnavailable,
    required this.logItems,
    required this.runningAll,
    required this.onRunAll,
  });

  final IpfsNodeController controller;
  final CapabilitySet capabilities;
  final Set<Capability> temporarilyUnavailable;
  final List<IpfsOperationLogItem> logItems;
  final bool runningAll;
  final VoidCallback? onRunAll;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IpfsIpnsPanel(controller: controller),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: runningAll ? null : onRunAll,
              icon: const Icon(Icons.playlist_play),
              label: Text(runningAll ? '运行中…' : '运行全部演示'),
            ),
          ),
          const SizedBox(height: 12),
          IpfsCapabilityPanel(
            capabilities: capabilities,
            temporarilyUnavailable: temporarilyUnavailable,
          ),
          const SizedBox(height: 12),
          IpfsOperationLogPanel(items: logItems),
        ],
      );
}
