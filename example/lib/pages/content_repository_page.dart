import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

class ContentRepositoryPage extends StatefulWidget {
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
  State<ContentRepositoryPage> createState() => _ContentRepositoryPageState();
}

class _ContentRepositoryPageState extends State<ContentRepositoryPage> {
  String? _selectedCid;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IpfsRepositoryPanel(
            repositoryPath: widget.repositoryPath,
            contentCount: null,
            pinCount: widget.pinCount,
          ),
          IpfsContentAddPanel(
            controller: widget.controller,
            publicationSupported: widget.publicationSupported,
            onAdded: (result) => setState(() => _selectedCid = result.cid),
          ),
          IpfsCidFetchPanel(controller: widget.controller),
          IpfsCidPublicationPanel(
            controller: widget.controller,
            initialCid: _selectedCid,
            publicationSupported: widget.publicationSupported,
          ),
          IpfsPinPanel(controller: widget.controller),
          IpfsPinListPanel(controller: widget.controller),
        ].expand((widget) => [widget, const SizedBox(height: 12)]).toList(),
      );
}
