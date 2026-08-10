import 'package:ipfs_node_flutter_native/ipfs_node_flutter_native.dart';

/// Registers the packaged Go ABI backend on native platforms.
void register() => IpfsNodeFlutterNative.registerWith();
