import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

class IpfsCapabilityPanel extends StatelessWidget {
  const IpfsCapabilityPanel({
    super.key,
    required this.capabilities,
    this.temporarilyUnavailable = const {},
  });

  final CapabilitySet capabilities;
  final Set<Capability> temporarilyUnavailable;

  List<Capability> get _orderedCapabilities {
    final values = [...Capability.values];
    values.sort((left, right) {
      final leftSupported = capabilities.contains(left) ? 0 : 1;
      final rightSupported = capabilities.contains(right) ? 0 : 1;
      return leftSupported.compareTo(rightSupported);
    });
    return values;
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('能力矩阵', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 360,
                child: ListView(
                  children: [
                    for (final capability in _orderedCapabilities)
                      ListTile(
                        dense: true,
                        title: Text(capability.name),
                        trailing: Text(_status(capability)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  String _status(Capability capability) {
    if (!capabilities.contains(capability)) return '不支持';
    if (temporarilyUnavailable.contains(capability)) return '暂不可用';
    return '支持';
  }
}
