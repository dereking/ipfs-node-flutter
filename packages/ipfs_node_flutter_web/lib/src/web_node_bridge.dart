import 'dart:typed_data';

import 'package:ipfs_node_flutter_platform_interface/ipfs_node_platform_interface.dart';

/// Minimal boundary between the Dart platform adapter and the Helia runtime.
abstract interface class WebNodeBridge {
  CapabilitySet get capabilities;

  Future<void> start({required List<String> bootstrapPeers});

  Future<void> stop();

  Future<String> addBytes(Uint8List bytes);

  Future<Uint8List> getBytes(String cid);
}
