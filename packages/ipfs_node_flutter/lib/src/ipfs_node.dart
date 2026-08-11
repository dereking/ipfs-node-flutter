import 'dart:convert';
import 'dart:typed_data';

import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

final class IpfsNode {
  IpfsNode({IpfsNodePlatform? platform})
      : _platform = platform ?? IpfsNodePlatform.instance.create();

  final IpfsNodePlatform _platform;
  CapabilitySet _capabilities = const CapabilitySet.empty();

  Future<void> start(NodeConfig config) async {
    await _platform.start(config);
    await capabilities();
  }

  Future<void> stop() => _platform.stop();

  Future<void> dispose() => _platform.dispose();

  Future<NodeStatus> status() => _platform.status();

  Future<CapabilitySet> capabilities() async {
    _capabilities = await _platform.capabilities();
    return _capabilities;
  }

  /// Retrieves and verifies one raw IPFS block by CID.
  Future<Uint8List> getBlock(
    String cid, {
    Duration timeout = const Duration(seconds: 180),
  }) =>
      _platform.getBlock(cid, timeout: timeout);

  /// Stores raw bytes as an IPFS content root and returns its CID.
  Future<IpfsAddResult> addBytes(Uint8List bytes) => _platform.addBytes(bytes);

  /// Whether this node is ready to announce content through its router.
  Future<bool> networkReady() => _platform.networkReady();

  /// Announces an already-local content root through the configured DHT.
  Future<void> provide(
    String cid, {
    Duration timeout = const Duration(seconds: 60),
  }) =>
      _platform.provide(cid, timeout: timeout);

  /// Durably queues a local root for eventual provider publication.
  Future<void> startProviding(String cid) => _platform.startProviding(cid);

  /// Returns strict provider-publication evidence for [cid].
  Future<IpfsPublicationStatus> publicationStatus(String cid) =>
      _platform.publicationStatus(cid);

  /// Returns every root enrolled in provider publication.
  Future<List<IpfsPublicationStatus>> listPublicationStatuses() =>
      _platform.listPublicationStatuses();

  /// Stores bytes locally, then waits for their provider announcement.
  Future<IpfsAddResult> addAndProvide(
    Uint8List bytes, {
    Duration timeout = const Duration(seconds: 60),
  }) =>
      _platform.addAndProvide(bytes, timeout: timeout);

  /// Stores [text] as an IPFS content root and returns its CID.
  Future<IpfsAddResult> addText(String text) =>
      _platform.addBytes(utf8.encode(text));

  /// Pins a content root so its block stays available locally.
  Future<void> pin(String cid) => _platform.pin(cid);

  /// Removes a local pin for a content root.
  Future<void> unpin(String cid) => _platform.unpin(cid);

  /// Lists the locally pinned content roots.
  Future<List<IpfsPinInfo>> listPins() => _platform.listPins();

  /// Returns the peers with open connections to this node.
  Future<List<IpfsPeerInfo>> swarmPeers() => _platform.swarmPeers();

  /// Dials a peer encoded as a p2p multiaddr.
  Future<void> swarmConnect(String multiaddr) =>
      _platform.swarmConnect(multiaddr);

  /// Closes all connections to a peer.
  Future<void> swarmDisconnect(String peerId) =>
      _platform.swarmDisconnect(peerId);

  /// Returns the configured bootstrap multiaddrs.
  Future<List<String>> bootstrapList() => _platform.bootstrapList();

  /// Validates and records a bootstrap multiaddr.
  Future<void> bootstrapAdd(String multiaddr) =>
      _platform.bootstrapAdd(multiaddr);

  /// Removes a bootstrap multiaddr.
  Future<void> bootstrapRemove(String multiaddr) =>
      _platform.bootstrapRemove(multiaddr);

  /// Returns the current bitswap counters.
  Future<IpfsBitswapStats> bitswapStats() => _platform.bitswapStats();

  /// Searches the DHT for peers advertising a content root.
  Future<List<IpfsPeerInfo>> findProviders(
    String cid, {
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _platform.findProviders(cid, timeout: timeout);

  /// Locates a peer on the DHT and returns its addresses.
  Future<IpfsPeerInfo> findPeer(
    String peerId, {
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _platform.findPeer(peerId, timeout: timeout);

  /// Publishes a content root under this node's IPNS name.
  Future<String> publishName(
    String cid, {
    Duration timeout = const Duration(seconds: 60),
  }) =>
      _platform.publishName(cid, timeout: timeout);

  /// Resolves an IPNS name to a content path.
  Future<String> resolveName(
    String name, {
    Duration timeout = const Duration(seconds: 60),
  }) =>
      _platform.resolveName(name, timeout: timeout);

  /// Returns the local IPNS keys.
  Future<List<IpfsKeyInfo>> listKeys() => _platform.listKeys();

  void require(Capability capability) {
    if (!_capabilities.contains(capability)) {
      throw UnsupportedCapabilityException(capability);
    }
  }
}
