import 'capability.dart';
import 'node_config.dart';
import 'node_status.dart';

/// Internal adapter boundary until the platform interface package is available.
abstract interface class IpfsNodeBackend {
  Future<void> start(NodeConfig config);

  Future<void> stop();

  Future<NodeStatus> status();

  Future<Set<Capability>> capabilities();
}
