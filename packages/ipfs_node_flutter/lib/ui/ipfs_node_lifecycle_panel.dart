import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// Starts, stops and observes one shared [IpfsNode].
class IpfsNodeLifecyclePanel extends StatelessWidget {
  const IpfsNodeLifecyclePanel({
    super.key,
    required this.controller,
    this.config,
  });

  final IpfsNodeController controller;

  /// Config used when the start button is pressed. Defaults to a public node.
  final NodeConfig? config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('节点控制', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          IpfsNodeStatusPanel(
            status: controller.status,
            loading: controller.loading,
            error: controller.error,
            onRefresh: controller.loading ? null : controller.refresh,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: controller.running
                ? FilledButton.tonalIcon(
                    onPressed: controller.loading ? null : controller.stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('停止'),
                  )
                : FilledButton.icon(
                    onPressed: controller.loading
                        ? null
                        : () => controller.start(config ?? NodeConfig.public()),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('启动'),
                  ),
          ),
        ],
      ),
    );
  }
}
