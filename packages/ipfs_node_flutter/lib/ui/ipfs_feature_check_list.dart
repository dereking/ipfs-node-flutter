import 'package:flutter/material.dart';

import 'ipfs_feature_check.dart';
import 'ipfs_feature_check_card.dart';

/// A vertical stack of independent [IpfsFeatureCheckCard]s.
class IpfsFeatureCheckList extends StatelessWidget {
  const IpfsFeatureCheckList({super.key, required this.checks});

  final List<IpfsFeatureCheck> checks;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final check in checks) ...[
            IpfsFeatureCheckCard(check: check),
            const SizedBox(height: 12),
          ],
        ],
      );
}
