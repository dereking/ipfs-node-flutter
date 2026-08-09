import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// A self-contained check of a single IPFS feature.
///
/// The [run] callback receives an isolated [IpfsNode] that it configures
/// itself (for example via [IpfsNode.start]) and returns a human-readable
/// summary on success or throws on failure. The node is created and disposed
/// by the widget that drives the check, so [run] must not dispose it.
class IpfsFeatureCheck {
  const IpfsFeatureCheck({
    required this.title,
    required this.description,
    required this.run,
  });

  /// Short display title.
  final String title;

  /// One-line explanation shown under the title.
  final String description;

  /// Executes the check and returns a summary on success.
  final Future<String> Function(IpfsNode node) run;
}
