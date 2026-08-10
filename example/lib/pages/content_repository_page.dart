import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

class ContentRepositoryPage extends StatelessWidget {
  const ContentRepositoryPage({
    super.key,
    required this.controller,
    required this.repositoryPath,
    required this.pinCount,
    required this.publicationSupported,
  });

  final IpfsNodeController controller;
  final String repositoryPath;
  final int pinCount;
  final bool publicationSupported;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IpfsRepositoryPanel(
            repositoryPath: repositoryPath,
            contentCount: null,
            pinCount: pinCount,
          ),
          IpfsContentAddPanel(controller: controller),
          IpfsCidFetchPanel(controller: controller),
          IpfsCidPublicationPanel(
            controller: controller,
            publicationSupported: publicationSupported,
          ),
          IpfsPinPanel(controller: controller),
          IpfsPinListPanel(controller: controller),
        ].expand((widget) => [widget, const SizedBox(height: 12)]).toList(),
      );
}
