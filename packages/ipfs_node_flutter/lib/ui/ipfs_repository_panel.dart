import 'package:flutter/material.dart';

class IpfsRepositoryPanel extends StatelessWidget {
  const IpfsRepositoryPanel({
    super.key,
    required this.repositoryPath,
    required this.contentCount,
    required this.pinCount,
  });

  final String repositoryPath;

  /// Number of locally recorded root CIDs, when exposed by the host app.
  final int? contentCount;
  final int pinCount;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('本地仓库', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText('目录：$repositoryPath'),
            Text(contentCount == null
                ? '内容根：—（SDK 暂未暴露统计）'
                : '内容根：$contentCount 个'),
            Text('Pin：$pinCount 个'),
          ]),
        ),
      );
}
