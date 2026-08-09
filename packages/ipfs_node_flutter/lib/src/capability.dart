enum Capability {
  inboundListen,
  tcp,
  quic,
  webRtc,
  webTransport,
  dhtRouting,
  mdns,
  privateSwarmKey,
  unixfs,
  car,
  ipns,
  pubsub,
  remotePinning,
}

final class CapabilitySet {
  CapabilitySet(Iterable<Capability> capabilities)
      : _capabilities = Set.unmodifiable(capabilities);

  const CapabilitySet.empty() : _capabilities = const {};

  final Set<Capability> _capabilities;

  bool contains(Capability capability) => _capabilities.contains(capability);

  Set<Capability> get values => _capabilities;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CapabilitySet &&
        _capabilities.length == other._capabilities.length &&
        _capabilities.containsAll(other._capabilities);
  }

  @override
  int get hashCode => Object.hashAllUnordered(_capabilities);
}
