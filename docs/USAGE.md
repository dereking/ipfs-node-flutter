# ipfs-node-flutter SDK 使用指引

本文档覆盖 `ipfs-node-flutter` 的完整使用方式：架构原理、环境安装、统一 API 的逐个功能代码片段、可复用 UI 组件、以及各平台差异与限制。

- [1. 架构总览](#1-架构总览)
- [2. 环境准备与安装](#2-环境准备与安装)
- [3. 快速开始](#3-快速开始)
- [4. 功能详解（代码片段）](#4-功能详解代码片段)
  - [4.1 节点生命周期与状态](#41-节点生命周期与状态)
  - [4.2 能力集](#42-能力集)
  - [4.3 添加内容 addBytes / addText](#43-添加内容-addbytes--addtext)
  - [4.4 按 CID 取回 getBlock](#44-按-cid-取回-getblock)
  - [4.5 固定 pin / unpin / listPins](#45-固定-pin--unpin--listpins)
  - [4.6 Swarm 网络](#46-swarm-网络)
  - [4.7 Bootstrap 管理](#47-bootstrap-管理)
  - [4.8 Bitswap 统计](#48-bitswap-统计)
  - [4.9 DHT 查询 findProviders / findPeer](#49-dht-查询-findproviders--findpeer)
  - [4.10 IPNS publishName / resolveName / listKeys](#410-ipns-publishname--resolvename--listkeys)
  - [4.11 错误处理](#411-错误处理)
- [5. 可复用 UI 组件](#5-可复用-ui-组件)
- [6. 平台差异与限制](#6-平台差异与限制)
- [7. 参考实现](#7-参考实现)

---

## 1. 架构总览

SDK 通过 **统一 API** 屏蔽平台差异：业务代码只依赖 `IpfsNode` 门面类，底层由平台接口 `IpfsNodePlatform` 派发到不同的底层实现。

```
┌─────────────────────────────────────────────────────┐
│  业务代码（状态管理、UI 等）                           │
│  IpfsNode.addText / getBlock / pin / ...            │
└──────────────────────┬──────────────────────────────┘
                       │
          ┌────────────▼────────────┐
          │  ipfs_node_flutter       │  ← 门面 + 平台注册
          │  IpfsNode (facade)       │
          └────────────┬────────────┘
                       │
          ┌────────────▼────────────┐
          │  IpfsNodePlatform        │  ← 平台接口（统一 API 契约）
          │  (platform_interface)    │
          └───────┬──────────┬──────┘
                  │          │
     ┌────────────▼───┐  ┌───▼──────────────────┐
     │ native 底层      │  │ web 底层              │
     │ IpfsNodeFlutter │  │ IpfsNodeFlutterWeb   │
     │ Native          │  │ (Helia)              │
     │  └ dart:ffi     │  │  └ dart:js_interop   │
     │  └ Go dylib     │  │  └ helia_adapter.js  │
     └────────────────┘  └──────────────────────┘
```

### 1.1 Native 底层（Go）

- 核心逻辑由 **Go** 实现（`native/go/internal/core`），使用 boxo / libp2p / Bitswap / DHT / namesys。
- 编译为平台共享库（macOS `libipfs_node_core.dylib`、Linux/Android `libipfs_node_core.so`、Windows `ipfs_node_core.dll`），通过 **C ABI** 暴露（`ipfs_node_*` 系列函数）。
- Dart 侧 `IpfsNodeFlutterNative` 用 **`dart:ffi`** `DynamicLibrary.open(...)` 加载，`lookupFunction` 绑定符号。
- **非阻塞**：所有阻塞式 FFI 调用都在 worker isolate（`Isolate.run`）中执行，UI 线程不会被网络操作（bootstrap、Bitswap、DHT、IPNS）卡死，进度指示器可正常渲染。

### 1.2 Web 底层（Helia / JS）

- 核心逻辑由 **JavaScript** 实现（Helia + js-libp2p），源码在 `packages/ipfs_node_flutter_web/javascript/src/helia_adapter.js`。
- 用 **esbuild** 打包成单个 IIFE 脚本 `web/helia_adapter.js`，暴露全局对象 `IpfsNodeFlutterHelia`：

  ```sh
  cd packages/ipfs_node_flutter_web/javascript
  npm install --ignore-scripts && npm run build
  ```

- **嵌入 Flutter runtime 的方式**：Dart 通过 `dart:js_interop` 声明 `@JS('IpfsNodeFlutterHelia.xxx')` 外部函数直接调用浏览器里的 JS；JS 侧函数以 `(node, …, resolve, reject)` 回调返回结果，Dart 侧用 `Completer` 包成 `Future`（见 `web_node_bridge_browser.dart`）。
- **适配器脚本加载（用户无感知）**：`helia_adapter.js` 是 SDK 包 pubspec 声明的 Flutter asset（`flutter: assets: - web/helia_adapter.js`），`flutter pub add` 后由 Flutter 构建自动打进产物；运行时桥自动向 DOM 注入 `<script src="assets/packages/ipfs_node_flutter_web/web/helia_adapter.js">`。**用户不需要手动修改任何 HTML 或引入任何 JS。**
- 数据存储使用浏览器 **IndexedDB**（`blockstore-idb`）；传输层使用 WebRTC / WebTransport / WSS / circuit relay。

### 1.3 统一 API 契约

所有功能都在 `IpfsNodePlatform` 上定义，native 与 web 实现同一套方法（web 不支持的功能抛出类型化错误，见 [6. 平台差异](#6-平台差异与限制)）。因此**同一份业务代码可以跑在 macOS、Windows、Linux、Android、iOS 与 Web**。

---

## 2. 环境准备与安装

### 2.1 依赖（只需一个包）

SDK 采用 Flutter **联邦插件**架构：用户**只声明 `ipfs_node_flutter` 一个依赖**，Flutter 工具链会按目标平台自动解析并注册底层实现（桌面/移动 → `ipfs_node_flutter_native`，Web → `ipfs_node_flutter_web`），不需要手动加实现包。

```yaml
dependencies:
  flutter:
    sdk: flutter
  ipfs_node_flutter: ^1.0.0   # 或 path 依赖（本仓库 workspace）
```

> 需要真机/集成测试的场合，可把实现包加为 `dev_dependencies`（见 `example/pubspec.yaml`）。

### 2.2 平台注册（自动 + 幂等兜底）

`ipfs_node_flutter` 通过 pubspec 的 `flutter: plugin: platforms: {default_package: ...}` 声明各平台的默认实现；构建时 `flutter` 工具生成插件注册器（web 生成 `web_plugin_registrant.dart` 调用 `IpfsNodeFlutterWeb.registerWith(registrar)`，native 生成 `dart_plugin_registrant.dart` 调用 `IpfsNodeFlutterNative.registerWith()`），在 app 启动时自动完成注册。

**推荐做法**：在 `main()` 里再显式注册一次作为**幂等安全网**（条件导入按平台选实现，覆盖插件注册器因构建缓存异常而未生效的情况）：

`lib/platform_registration.dart`：

```dart
import 'platform_registration_io.dart'
    if (dart.library.js_interop) 'platform_registration_web.dart'
    as registration;

void registerIpfsNodePlatform() => registration.register();
```

`lib/platform_registration_io.dart` / `_web.dart`：

```dart
// io
void register() => IpfsNodeFlutterNative.registerWith();
// web
void register() => IpfsNodeFlutterWeb.registerWith();
```

`lib/main.dart`：

```dart
import 'package:flutter/material.dart';
import 'platform_registration.dart' as platform;

void main() {
  platform.registerIpfsNodePlatform();   // 幂等；与自动注册不冲突
  runApp(const MyApp());
}
```

> 纯消费者的最小接入可以省略这一步（自动注册即可）；带显式注册能让应用在插件注册器缓存异常时也始终可用。未注册任何实现时，`stop()`/`dispose()` 为安全 no-op，不会崩溃。

### 2.3 Native 底层依赖嵌入

- **macOS**：example 的 Xcode 构建阶段会把 `native/go/dist/libipfs_node_core.dylib` 嵌入到 App 的 Frameworks 目录并签名。参考 `example/macos/Runner.xcodeproj`。
- **Windows**：example 的 `example/windows/CMakeLists.txt` 会在构建时自动执行 `go build -buildmode=c-shared` 生成 `ipfs_node_core.dll` 并安装到可执行文件同目录（需要 `PATH` 上有带 cgo 的 Go 工具链，如 mingw-w64 gcc）。也可手动 `make -C native/go build-windows`。
- 其他平台需以相应共享库嵌入（Linux/Android `.so`），并在 `_defaultArtifactName()` 的约定路径提供。

### 2.4 Web 适配器资源（无需手动配置）

用户**完全不需要**在 HTML 里添加任何 `<script>` 或拷贝 JS 文件。`ipfs_node_flutter_web` 的 pubspec 声明了 `web/helia_adapter.js` 作为 asset，Flutter 构建自动打包，桥在运行时自动加载。

Web 端完整接入也只有三步（`registerWith` 由构建工具自动调用）：

```sh
flutter pub add ipfs_node_flutter
```

```dart
// main.dart —— 无需任何平台注册代码
void main() {
  runApp(const MyApp());
}
```

之后的使用与 native 完全一致（见 [第 3 节](#3-快速开始)）。

> 高级场景：若想覆盖默认适配器，可在自己 app 的 `web/helia_adapter.js` 放置同名文件（运行时优先使用 Flutter 打包的 asset，其次才是这个覆盖项）。普通用户无需理会。

---

## 3. 快速开始

```dart
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

final node = IpfsNode();               // 使用已注册的平台底层

// 启动公网节点
await node.start(NodeConfig.public(repositoryPath: '/app/support/ipfs-node'));

// 查看状态
final status = await node.status();
print(status.peerId);                  // 本节点 Peer ID
print(status.connectedPeers);          // 已连接的 bootstrap peers
print(status.listenAddrs);             // 监听地址
print(status.bootstrapErrors);         // 非致命 bootstrap 错误

// 添加内容并取回
final added = await node.addText('Hello IPFS');
final bytes = await node.getBlock(added.cid);
print(String.fromCharCodes(bytes));    // Hello IPFS

// 停止（可重复调用）
await node.stop();

// 释放底层资源
await node.dispose();
```

> `start` 内部会自动拉取一次 `capabilities()`，之后才能用 `node.require(...)` 检查能力。

---

## 4. 功能详解（代码片段）

### 4.1 节点生命周期与状态

```dart
// 公网节点（未指定 bootstrap 时使用 Boxo 官方公共 bootstrap）
await node.start(NodeConfig.public(repositoryPath: '/app/support/ipfs-node'));

// 私有网络：32 字节 PSK + 只属于该私网的 bootstrap 列表
await node.start(NodeConfig.private(
  repositoryPath: '/app/support/ipfs-node/private/team-a',
  swarmKey: List<int>.filled(32, 7),
  bootstrapPeers: ['/dns4/.../tcp/4001/p2p/<peer>'],
));

// 状态
final status = await node.status();
status.lifecycle;                     // NodeLifecycle.stopped/starting/running/degraded/stopping/failed
status.peerId;                        // String?
status.safeDiagnostic;                // String?

// 停止 / 释放（幂等）
await node.stop();
await node.dispose();
```

### 4.2 能力集

```dart
final capabilities = await node.capabilities();      // CapabilitySet
capabilities.contains(Capability.dhtRouting);        // bool

// 需要某能力时直接断言，缺失会抛 UnsupportedCapabilityException
node.require(Capability.dhtRouting);
node.require(Capability.tcp);
```

能力枚举还包括 `providerRouting` 与 `publicPublication`。Native 公共节点
同时声明两者；Native 私有节点声明 `privateSwarmKey` 和
`providerRouting`，但不声明 `publicPublication`；Web 两者均不声明。
调用可选功能前应先用 `contains()` 或 `require()` 检查。

### 4.3 添加内容 addBytes / addText

```dart
import 'dart:convert';
import 'dart:typed_data';

// 文本
final result = await node.addText('Hello IPFS');
print(result.cid);                    // bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244
print(result.bytes);                  // 字节数

// 原始字节
final raw = await node.addBytes(Uint8List.fromList([0, 1, 2, 255]));

// 任意二进制（native）等价于 `ipfs add` CIDv1/raw-leaves：小内容直接得到 raw block CID
```

本地保存与公网发布是两个不同结果：

```dart
final local = await node.addText('仅保存到本机仓库');

try {
  final published = await node.addAndProvide(utf8.encode('保存并严格发布'));
  print(published.cid); // 远端 DHT quorum 已回读确认
} on IpfsPublicationException catch (error) {
  // 写入与发布结果不会混淆：CID 已持久化，可稍后继续发布。
  print('本地 CID: ${error.result.cid}，发布失败: ${error.message}');
}

// 同步严格发布：只有远端 DHT peers 回读到本节点 provider record 才成功。
await node.provide(local.cid);

// 或持久化加入单一后台队列；重启后继续，指数退避并定期 reprovide。
await node.startProviding(local.cid);
final status = await node.publicationStatus(local.cid);
final queue = await node.listPublicationStatuses();
print('${status.state}: ${status.confirmedPeers}/${status.requiredConfirmations}');
```

Native 只有在 DHT 已就绪，且 relay reservation 或公网直连地址至少一项
可用时，`networkReady()` 才返回 true。`addAndProvide` 在网络未就绪或远端
确认数不足时抛 `IpfsPublicationException`，其中仍携带已持久化的 CID。
后台队列保存 `pending / confirmed / degraded / failed` 状态、尝试次数、远端
写入/确认计数、最近错误和下次重试时间。Relay/公网地址从不可用变为可用或
地址发生变化时会立即重试。Web 不支持 provider 发布及发布队列；相关 API
抛 `UnsupportedCapabilityException`，IndexedDB 添加、读取和 Pin 仍可使用。

`confirmed` 严格表示远端 DHT Peer 已回读到本节点的 provider record，不表示
未来任意读取方一定完成下载；节点仍需保持在线且 Bitswap 连接可用。尤其是
Boxo/Kubo 会把纯 circuit-relay 连接标记为 limited，通常需要公网直连或
DCUtR hole-punch 升级后才会把该 Peer 用于 Bitswap。Relay reservation 仍是
可发布/可拨号的必要证据之一，但 UI 分别展示 relay、DHT 发布确认和 Bitswap
传输状态，不能把三者合并成同一个“上传成功”。

私有网络的就绪条件是 DHT 已就绪且至少连接一个使用相同 PSK 的私有 Peer；
它不要求公网地址。私有节点显式使用 DHT Server 模式，使小型私网也能完成
provider routing。不同 PSK 的节点无法建立连接。

> **跨节点取回**：native 必须保持在线，并通过 `provide` 或
> `addAndProvide` 成功写入 provider record。单独 `addBytes`、`addText` 或
> `pin` 只保证本地持久化，不承诺公网可发现。Web 只能读取本地内容或已连接
> peer 可提供的内容，不发布 provider record。

### 4.4 按 CID 取回 getBlock

```dart
final bytes = await node.getBlock(
  'bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244',
  timeout: const Duration(seconds: 180),   // 默认 180s
);

// native：小内容（raw block）即原文；未在本地时经 Bitswap/DHT 从公网取回并校验 CID
// web：raw block（bafkrei...）与 UnixFS 文件均可读取
final text = utf8.decode(bytes);           // 可能抛 FormatException（非 UTF-8 内容）
```

### 4.5 固定 pin / unpin / listPins

```dart
// 固定（确保根 block 本地可用；未命中时先经 Bitswap 取回）
await node.pin(added.cid);

// 列出固定
final pins = await node.listPins();        // List<IpfsPinInfo>
for (final pin in pins) {
  print(pin.cid);                          // CID
  print(pin.type);                         // IpfsPinType.direct / recursive
  print(pin.pinnedAt);                     // DateTime?
}

// 取消固定
await node.unpin(added.cid);
```

### 4.6 Swarm 网络

```dart
// 列出当前连接 peers
final peers = await node.swarmPeers();     // List<IpfsPeerInfo>
for (final peer in peers) {
  print(peer.id);                          // peer ID
  print(peer.addrs);                       // List<String> 多地址
}

// 主动连接（p2p multiaddr）
await node.swarmConnect(
  '/ip4/1.2.3.4/tcp/4001/p2p/Qm...',
);

// 断开
await node.swarmDisconnect('Qm...');
```

### 4.7 Bootstrap 管理

```dart
final bootstraps = await node.bootstrapList();    // List<String>

await node.bootstrapAdd(
  '/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN',
);
await node.bootstrapRemove('/dnsaddr/...');
```

### 4.8 Bitswap 统计

```dart
final stats = await node.bitswapStats();   // IpfsBitswapStats
print(stats.blocksReceived);               // 收到块数
print(stats.dataReceived);                 // 收到字节数
print(stats.wantlist);                     // wantlist 条目数
print(stats.messagesSent);                 // 发送消息数
print(stats.messagesReceived);             // 收到消息数
```

> boxo v0.42 的 bitswap 客户端只提供接收侧块/字节计数与消息收发数，没有发送侧块级计数。

### 4.9 DHT 查询 findProviders / findPeer

```dart
// 查询某个 CID 的 provider
final providers = await node.findProviders(
  'bafkreidfdrlkeq4m4xnxuyx6iae76fdm4wgl5d4xzsb77ixhyqwumhz244',
  timeout: const Duration(seconds: 30),
);
for (final provider in providers) {
  print(provider.id);
}

// 定位某个 peer 的地址（native 下查自己会直接返回本节点监听地址）
final info = await node.findPeer('Qm...', timeout: const Duration(seconds: 30));
print(info.addrs);
```

### 4.10 IPNS publishName / resolveName / listKeys

> 注意：IPNS 发布/解析依赖**公网 DHT**，离线或浏览器环境不可用（web 抛 `UnsupportedCapabilityException`）。

```dart
// 把内容 CID 发布为本节点的 IPNS 名称
final name = await node.publishName(added.cid);     // 形如 <peerID>
print(name);

// 解析 IPNS 名称 -> 内容路径
final path = await node.resolveName('/ipns/$name'); // 形如 /ipfs/<cid>
print(path);

// 本地 keys（目前只有 self）
final keys = await node.listKeys();                 // List<IpfsKeyInfo>
for (final key in keys) {
  print('${key.name}: ${key.peerId}');
}
```

### 4.11 错误处理

统一入口：所有操作失败都会抛异常，业务侧捕获并展示即可：

```dart
try {
  final bytes = await node.getBlock('not-a-cid');
} on IpfsNodeException catch (e) {
  // 平台契约类型化错误（UnsupportedCapabilityException 等）
  print(e);
} catch (e) {
  // 原生底层会抛 NativeNodeRequestException / NativeNodeProtocolException 等；
  // web 端不支持的功能抛 UnsupportedError / UnsupportedCapabilityException
  print(e);
}
```

---

## 5. 可复用 UI 组件

SDK 在 `ipfs_node_flutter/lib/ui` 提供可直接使用的组件（全部通过 `package:ipfs_node_flutter/ipfs_node_flutter.dart` 导出），业务代码无需自己写 IPFS 交互 UI。

### 5.1 常用功能组件

| 组件 | 功能 | 说明 |
|---|---|---|
| `IpfsNodeController` | 共享节点生命周期（ChangeNotifier） | 持有单个 `IpfsNode`，提供 start/stop/status/error/loading，供多个面板共用 |
| `IpfsNodeLifecyclePanel` | 启动/停止 + 状态 | 内嵌 `IpfsNodeStatusPanel` |
| `IpfsNodeStatusPanel` | 状态展示 | 生命周期/Peer ID/监听/连接/bootstrap 错误 |
| `IpfsCidFetchPanel` | 按 CID 取回 | UTF-8 可解码显示文本，否则 base64 |
| `IpfsContentAddPanel` | 添加文本内容 | 返回 CID + 复制按钮 |
| `IpfsPinPanel` | 固定/取消固定 | 输入 CID |
| `IpfsPinListPanel` | 固定列表 | 分类、取消固定、刷新 |
| `IpfsSwarmPanel` | peers 列表 + 连接 | 断开单个 peer |
| `IpfsBootstrapPanel` | bootstrap 增删查 | |
| `IpfsBitswapPanel` | bitswap 统计 | |
| `IpfsDhtPanel` | findProviders 查询 | |
| `IpfsFindPeerPanel` | findPeer 查询 | |
| `IpfsIpnsPanel` | IPNS 发布/解析 | |
| `IpfsCapabilityPanel` | 能力支持/暂不可用矩阵 | |
| `IpfsOperationLogPanel` | 全流程状态、耗时与错误 | |

### 5.2 测试组件

| 组件 | 功能 |
|---|---|
| `IpfsFeatureCheck` | 单个可运行功能测试的模型（title/description/`run(IpfsNode)`） |
| `IpfsFeatureCheckCard` | 单个测试卡片（idle/running/passed/failed，每次运行独立节点） |
| `IpfsFeatureCheckList` | 测试卡片列表 |

### 5.3 集成示例

```dart
import 'package:flutter/material.dart';
import 'package:ipfs_node_flutter/ipfs_node_flutter.dart';

class IpfsPage extends StatefulWidget {
  const IpfsPage({super.key, required this.repositoryPath});

  /// 由宿主应用通过 path_provider 等方式取得的稳定、可写目录。
  final String repositoryPath;

  @override
  State<IpfsPage> createState() => _IpfsPageState();
}

class _IpfsPageState extends State<IpfsPage> {
  late final IpfsNodeController _controller;
  int _pinListVersion = 0;

  @override
  void initState() {
    super.initState();
    _controller = IpfsNodeController();
    _controller.start(NodeConfig.public(
      repositoryPath: widget.repositoryPath,
    )); // 原生端自动开始；Web 可省略 repositoryPath
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IPFS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IpfsNodeLifecyclePanel(controller: _controller),
          const SizedBox(height: 12),
          IpfsCidFetchPanel(controller: _controller),
          const SizedBox(height: 12),
          IpfsContentAddPanel(controller: _controller),
          const SizedBox(height: 12),
          IpfsPinPanel(
            controller: _controller,
            onChanged: () => setState(() => _pinListVersion++),
          ),
          const SizedBox(height: 12),
          // 固定后通过改 ValueKey 刷新列表
          IpfsPinListPanel(
            key: ValueKey(_pinListVersion),
            controller: _controller,
          ),
        ],
      ),
    );
  }
}
```

> 节点由 `IpfsNodeController` 统一持有，多个面板共享同一个 `IpfsNode` 实例。

---

## 6. 平台差异与限制

### 6.1 Native（Go）

| 能力 | 状态 |
|---|---|
| start/stop/status/capabilities | ✅ |
| addBytes / getBlock（含公网 Bitswap/DHT 取回） | ✅ |
| 严格 provider 发布 / 持久化重试 / 远端确认状态 | ✅ |
| pin/unpin/listPins | ✅（direct 类型；未实现递归 DAG pin） |
| swarm / bootstrap / bitswap 统计 / DHT 查询 | ✅ |
| IPNS 发布/解析 | ✅（需公网 DHT） |

限制：
- blockstore、身份、Pin 与发布元数据持久化在必填 `repositoryPath`；同一仓库有进程锁。
- IPNS 离线不可用（依赖公网 DHT）。
- bitswap 无发送侧块级计数。

### 6.2 Web（Helia / 浏览器）

| 能力 | 状态 |
|---|---|
| start/stop/status/capabilities | ✅ |
| addBytes / getBytes（UnixFS + raw block） | ✅ |
| pin/unpin/listPins | ✅（IndexedDB 持久化） |
| swarmPeers / bootstrapList/Add/Remove | ✅ |
| findProviders / findPeer | ⚠️ 依赖 Helia routing（浏览器不跑原生 DHT，结果可能为空或报错） |
| bitswap 统计 | ✅ 本地跟踪的收发块/字节 + 在途 want 数（Helia 无消息级计数） |
| IPNS publishName/resolveName/listKeys | ✅ `@helia/ipns` + keychain（需浏览器可达的 DHT/记录分发） |

其他限制：
- 浏览器无原生 TCP/UDP 监听，入站不可达；仅 WebRTC / WebTransport / WSS / circuit relay。
- 浏览器仅保证本地/已连接 Peer 读取，不支持 provider 发布、发布队列或远端发布确认。
- 不支持 mDNS、私有 swarm key（`NodeConfig.private` 抛 `UnsupportedCapabilityException`）。
- 需浏览器支持 WebRTC 或 WebTransport，并允许 IndexedDB。
- 公共 bootstrap 需使用浏览器可拨号的 WSS 地址；不保证公网 CID 发现。

---

## 7. 参考实现

- **完整跨平台示例**：`example/` 使用一个共享 SDK 实例，提供“节点配置”、
  “内容与仓库”、“网络与路由”、“IPNS 与诊断”四页。公共/私有模式通过
  停止后切换，私网参数包括 PSK、bootstrap，以及可选 relay/Peer 白名单。
  “运行全部演示”会按依赖顺序执行本地存取、Pin、持久化发布队列、严格
  provider 确认、发布状态/重试计数、DHT、IPNS 和 Bitswap 统计。运行：

  ```sh
  flutter run -d macos   # native
  flutter run -d chrome  # web
  ```

- **Web 独立验证**：`packages/ipfs_node_flutter_web/example/`（Helia 浏览器集成冒烟测试）。
- **C ABI**：`native/go/dist/libipfs_node_core.h`（生成自 `make build-host`）。
- **测试**：`flutter test`（见根 README Validation 小节）。
