import 'package:flutter/material.dart';

enum IpfsOperationLogState { running, passed, waiting, failed }

final class IpfsOperationLogItem {
  const IpfsOperationLogItem({
    required this.operation,
    required this.state,
    required this.elapsed,
    this.details,
  });

  final String operation;
  final IpfsOperationLogState state;
  final Duration elapsed;
  final String? details;
}

class IpfsOperationLogPanel extends StatelessWidget {
  const IpfsOperationLogPanel({super.key, required this.items});

  final List<IpfsOperationLogItem> items;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('操作日志', style: Theme.of(context).textTheme.titleMedium),
              if (items.isEmpty) const Text('尚未运行演示'),
              for (final item in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.operation),
                  subtitle: item.details == null ? null : Text(item.details!),
                  trailing: Text(
                    '${_label(item.state)} · ${item.elapsed.inMilliseconds} ms',
                  ),
                ),
            ],
          ),
        ),
      );

  static String _label(IpfsOperationLogState state) => switch (state) {
        IpfsOperationLogState.running => '运行中',
        IpfsOperationLogState.passed => '已通过',
        IpfsOperationLogState.waiting => '等待条件',
        IpfsOperationLogState.failed => '失败',
      };
}
