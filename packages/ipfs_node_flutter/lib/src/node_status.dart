enum NodeLifecycle { stopped, starting, running, degraded, stopping, failed }

final class NodeStatus {
  const NodeStatus({required this.lifecycle, this.safeDiagnostic});

  final NodeLifecycle lifecycle;
  final String? safeDiagnostic;
}
