enum NodeLifecycle { stopped, starting, running, degraded, stopping, failed }

final class NodeStatus {
  const NodeStatus({required this.lifecycle, this.safeDiagnostic});

  const NodeStatus.running({String? safeDiagnostic})
      : this(lifecycle: NodeLifecycle.running, safeDiagnostic: safeDiagnostic);

  final NodeLifecycle lifecycle;
  final String? safeDiagnostic;

  @override
  bool operator ==(Object other) =>
      other is NodeStatus &&
      lifecycle == other.lifecycle &&
      safeDiagnostic == other.safeDiagnostic;

  @override
  int get hashCode => Object.hash(lifecycle, safeDiagnostic);
}
