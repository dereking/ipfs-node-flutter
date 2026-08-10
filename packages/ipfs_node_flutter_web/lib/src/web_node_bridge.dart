import 'dart:typed_data';

import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

/// Boundary between the Dart platform adapter and the Helia runtime.
abstract interface class WebNodeBridge {
  CapabilitySet get capabilities;

  Future<void> start({required List<String> bootstrapPeers});

  Future<void> stop();

  Future<String> addBytes(Uint8List bytes);

  Future<Uint8List> getBytes(String cid);

  Future<void> pin(String cid);

  Future<void> unpin(String cid);

  Future<List<IpfsPinInfo>> listPins();

  Future<List<IpfsPeerInfo>> swarmPeers();

  Future<List<String>> bootstrapList();

  Future<void> bootstrapAdd(String multiaddr);

  Future<void> bootstrapRemove(String multiaddr);

  Future<List<IpfsPeerInfo>> findProviders(
    String cid, {
    Duration timeout = const Duration(seconds: 30),
  });

  Future<IpfsPeerInfo> findPeer(
    String peerId, {
    Duration timeout = const Duration(seconds: 30),
  });

  Future<String> publishName(
    String cid, {
    Duration timeout = const Duration(seconds: 60),
  });

  Future<String> resolveName(
    String name, {
    Duration timeout = const Duration(seconds: 60),
  });

  Future<List<IpfsKeyInfo>> listKeys();

  Future<IpfsBitswapStats> bitswapStats();
}
