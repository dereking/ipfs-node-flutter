import 'dart:io';
import 'dart:convert';

import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

const documentedCid =
    'bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244';
const documentedContent = 'Hello IPFS\n';

const _unreachableBootstrapPeer = '/ip4/127.0.0.1/tcp/1/p2p/'
    'QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN';

/// Common IPFS feature checks. Each check receives an isolated node that it
/// configures itself; the driving widget creates and disposes that node.
const commonIpfsFeatureChecks = <IpfsFeatureCheck>[
  IpfsFeatureCheck(
    title: '节点生命周期',
    description: '启动 → 运行 → 停止 → 重启，验证状态机可重复。',
    run: _checkLifecycle,
  ),
  IpfsFeatureCheck(
    title: '节点身份与监听地址',
    description: '验证节点拥有唯一 Peer ID 和监听地址。',
    run: _checkIdentity,
  ),
  IpfsFeatureCheck(
    title: '能力集',
    description: '验证节点暴露 tcp / quic / dhtRouting 等能力。',
    run: _checkCapabilities,
  ),
  IpfsFeatureCheck(
    title: '无效 CID 错误处理',
    description: '验证非法 CID 返回类型化错误而非崩溃。',
    run: _checkInvalidCid,
  ),
  IpfsFeatureCheck(
    title: '公网取回固定内容',
    description: '通过 DHT / Bitswap 取回固定 CID 并校验内容。\n$documentedCid',
    run: _checkDocumentedCid,
  ),
];

Future<String> _checkLifecycle(IpfsNode node) async {
  await node.start(_offlinePublicConfig());
  final running = await node.status();
  if (running.lifecycle != NodeLifecycle.running) {
    throw StateError('启动后 lifecycle=${running.lifecycle}');
  }
  await node.stop();
  final stopped = await node.status();
  if (stopped.lifecycle != NodeLifecycle.stopped) {
    throw StateError('停止后 lifecycle=${stopped.lifecycle}');
  }
  await node.start(_offlinePublicConfig());
  final restarted = await node.status();
  if (restarted.lifecycle != NodeLifecycle.running) {
    throw StateError('重启后 lifecycle=${restarted.lifecycle}');
  }
  return 'start → running → stopped → running';
}

Future<String> _checkIdentity(IpfsNode node) async {
  await node.start(_offlinePublicConfig());
  final status = await node.status();
  final peerId = status.peerId;
  if (peerId == null || peerId.isEmpty) {
    throw StateError('节点没有 Peer ID');
  }
  if (status.listenAddrs.isEmpty) {
    throw StateError('节点没有监听地址');
  }
  return 'peerId=$peerId listenAddrs=${status.listenAddrs.length} 个';
}

Future<String> _checkCapabilities(IpfsNode node) async {
  await node.start(_offlinePublicConfig());
  const expected = {
    Capability.inboundListen,
    Capability.tcp,
    Capability.quic,
    Capability.dhtRouting,
  };
  for (final capability in expected) {
    node.require(capability);
  }
  final capabilities = await node.capabilities();
  final names = capabilities.values.map((value) => value.name).join(', ');
  return '能力齐全：$names';
}

Future<String> _checkInvalidCid(IpfsNode node) async {
  await node.start(_offlinePublicConfig());
  try {
    await node.getBlock('not-a-cid');
  } on Exception catch (error) {
    return '已按类型化错误拒绝：$error';
  }
  throw StateError('非法 CID 未报错');
}

Future<String> _checkDocumentedCid(IpfsNode node) async {
  await node.start(_publicConfig());
  final status = await node.status();
  final bytes = await node.getBlock(documentedCid);
  final content = utf8.decode(bytes);
  if (content != documentedContent) {
    throw StateError('CID 内容不匹配：${jsonEncode(content)}');
  }
  return 'connected=${status.connectedPeers.length} 内容=${jsonEncode(content)}';
}

NodeConfig _offlinePublicConfig() => NodeConfig.public(
      repositoryPath:
          Directory.systemTemp.createTempSync('ipfs-node-feature-check-').path,
      bootstrapPeers: const [_unreachableBootstrapPeer],
    );

NodeConfig _publicConfig() => NodeConfig.public(
      repositoryPath:
          Directory.systemTemp.createTempSync('ipfs-node-feature-check-').path,
    );
