import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

class NetworkRoutingPage extends StatelessWidget {
  const NetworkRoutingPage({
    super.key,
    required this.controller,
    required this.status,
    required this.networkReady,
    required this.publicationSupported,
  });

  final IpfsNodeController controller;
  final NodeStatus? status;
  final bool networkReady;
  final bool publicationSupported;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IpfsPublicationStatusPanel(
            status: status,
            networkReady: networkReady,
            publicAddressReady: networkReady && status?.relayReady != true,
            publicationSupported: publicationSupported,
          ),
          IpfsSwarmPanel(controller: controller),
          IpfsBootstrapPanel(controller: controller),
          IpfsBitswapPanel(controller: controller),
          IpfsDhtPanel(controller: controller),
          IpfsFindPeerPanel(controller: controller),
        ].expand((widget) => [widget, const SizedBox(height: 12)]).toList(),
      );
}
