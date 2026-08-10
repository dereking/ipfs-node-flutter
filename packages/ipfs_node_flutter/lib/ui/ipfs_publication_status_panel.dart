import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// Explains whether local content can currently be announced publicly.
class IpfsPublicationStatusPanel extends StatelessWidget {
  const IpfsPublicationStatusPanel({
    super.key,
    required this.status,
    required this.networkReady,
    required this.publicAddressReady,
    this.publicationSupported = true,
  });

  final NodeStatus? status;
  final bool networkReady;
  final bool publicAddressReady;
  final bool publicationSupported;

  @override
  Widget build(BuildContext context) {
    final dhtReady = status?.dhtReady == true;
    final relayReady = status?.relayReady == true;
    final reasons = <String>[
      if (!publicationSupported) '当前平台不支持公网发布',
      if (publicationSupported && !dhtReady) 'DHT 未就绪',
      if (publicationSupported && !relayReady) 'Relay 未就绪',
      if (publicationSupported && !publicAddressReady) '公网直连不可用',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('发布网络诊断', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('DHT：${dhtReady ? '已就绪' : '未就绪'}'),
            Text('Relay：${relayReady ? '已就绪' : '未就绪'}'),
            Text('公网直连：${publicAddressReady ? '可用' : '不可用'}'),
            const SizedBox(height: 8),
            Text(
              networkReady ? '可以发布内容' : '暂不可发布：${reasons.join('；')}',
              style: TextStyle(
                color: networkReady
                    ? Colors.green
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
