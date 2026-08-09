import 'capability.dart';

sealed class IpfsNodeException implements Exception {
  const IpfsNodeException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class UnsupportedCapabilityException extends IpfsNodeException {
  const UnsupportedCapabilityException(this.capability)
      : super('Unsupported capability: $capability');

  final Capability capability;
}
