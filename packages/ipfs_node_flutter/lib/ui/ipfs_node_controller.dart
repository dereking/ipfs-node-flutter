import 'package:flutter/foundation.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

/// Owns one [IpfsNode] and its lifecycle so feature widgets can share a single
/// node instance.
class IpfsNodeController extends ChangeNotifier {
  IpfsNodeController({IpfsNode? node}) : _node = node ?? IpfsNode();

  final IpfsNode _node;
  NodeStatus? _status;
  Object? _error;
  bool _loading = false;

  IpfsNode get node => _node;

  NodeStatus? get status => _status;

  Object? get error => _error;

  bool get loading => _loading;

  bool get running => _status?.lifecycle == NodeLifecycle.running;

  Future<void> start(NodeConfig config) async {
    if (_loading) return;
    _setLoading();
    try {
      await _node.start(config);
      _status = await _node.status();
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_loading) return;
    _setLoading();
    try {
      await _node.stop();
      _status = await _node.status();
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    try {
      _status = await _node.status();
    } catch (error) {
      _error = error;
    }
    notifyListeners();
  }

  void _setLoading() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    try {
      _node.dispose();
    } catch (_) {
      // Node disposal must not throw during controller teardown.
    }
    super.dispose();
  }
}
