# IPFS 常用功能 UI 清单

> 范围：ipfs-node-flutter SDK 的常用功能 UI 组件 + 对应 backend 扩展。
> 现状约束：native Go core 目前只实现 `getBlock`（raw block 取回）。除 A 外，其余模块都需同步扩展 Go core、Dart SDK 和 UI 组件。

## A. 节点管理（已有 ✅）

| 功能 | UI 组件 | 状态 |
|---|---|---|
| 启动/停止/重启 | `IpfsNodeLifecyclePanel` | 已有 |
| 状态 / Peer ID / 监听地址 | `IpfsNodeStatusPanel` | 已有 |
| 复制 Peer ID | `IpfsNodeStatusPanel` 小按钮 | 小增 |

## B. 内容上载（Add）

- Backend：Go core 新增 `add`（unixfs put + blockstore 持久化）；Dart 新增 `addText` / `addBytes` / `addFile`
- UI：
  - `IpfsContentAddPanel` — 文本/文件输入 → 返回 CID + 复制按钮
  - 上载进度条（大文件）
- 数据模型：`IpfsAddResult{cid, bytes, links}`

## C. 固定 Pin

- Backend：Go core 新增 `pin / unpin / listPins`（pin 状态需落盘）；Dart 新增 `pin()` / `unpin()` / `listPins()`
- UI：
  - `IpfsPinPanel` — 输入 CID 固定/取消
  - `IpfsPinListPanel` — 固定列表（recursive/direct 分类、取消按钮）
- 数据模型：`IpfsPinInfo{cid, type, pinnedAt}`

## D. IPNS

- Backend：Go core 新增 `name publish / resolve` + keys；Dart 新增对应方法
- UI：
  - `IpfsIpnsPanel` — 发布（CID + 别名 → IPNS 地址）、解析（名称 → CID）
  - 别名/keys 下拉选择

## E. P2P 网络

- Backend：Go core 新增 swarm / bootstrap；Dart 新增 `swarmPeers` / `swarmConnect` / `swarmDisconnect` / `bootstrapList` / `bootstrapAdd` / `bootstrapRemove`
- UI：
  - `IpfsSwarmPanel` — peers 列表 + 主动连接输入框
  - `IpfsBootstrapPanel` — bootstrap 增删查

## F. Bitswap / DHT

- Backend：Go core 新增 stats / findprovs；Dart 新增 `bitswapStats` / `findProviders`
- UI：
  - `IpfsBitswapPanel` — 收发块/字节统计卡片
  - `IpfsDhtPanel` — CID → findprovs 结果列表

## 共享数据模型（SDK ui 目录）

- `IpfsPeerInfo{id, addrs}`
- `IpfsPinInfo{cid, type, pinnedAt}`
- `IpfsBitswapStats{blocksSent, blocksReceived, dataSent, dataReceived}`
- `IpfsAddResult{cid, bytes, links}`

## 分阶段实施计划

1. **阶段 ①（已完成 ✅）**：B 内容上载 + C 固定 Pin
2. **阶段 ②（已完成 ✅）**：E P2P 网络（swarm + bootstrap）
3. **阶段 ③（已完成 ✅）**：F Bitswap / DHT
4. **阶段 ④（已完成 ✅）**：D IPNS

每阶段：Go core ABI → Dart SDK → SDK ui 组件 → example 集成 → 测试。

## 实施记录

### 阶段 ①：内容上载 + 固定
- Go core：`AddBytes`（小内容存 raw block，CID 与 `ipfs add` 互操作一致；大内容分片 + dag-pb 根）、`Pin` / `Unpin` / `ListPins`；ABI `ipfs_node_add_bytes` / `pin` / `unpin` / `list_pins`
- Dart SDK：`IpfsNode.addBytes/addText/pin/unpin/listPins` + `IpfsAddResult` / `IpfsPinInfo` / `IpfsPinType`
- SDK ui：`IpfsContentAddPanel`、`IpfsPinPanel`、`IpfsPinListPanel`
- 限制（后续处理）：blockstore 与 pin 状态为内存存储，节点停止后丢失；Pin 为 direct 类型（未实现递归 DAG pin）

### 阶段 ②③④：网络 / Bitswap / DHT / IPNS
- Go core：`SwarmPeers/Connect/Disconnect`、`BootstrapList/Add/Remove`、`BitswapStats`、`FindProviders`/`FindPeer`（FindPeer 支持查自身）、`PublishName/ResolveName/ListKeys`（namesys + kad 作 routing）；ABI 新增 12 个 `ipfs_node_*` 导出（共 24 个符号）
- Dart SDK：`swarmPeers/swarmConnect/swarmDisconnect/bootstrapList/bootstrapAdd/bootstrapRemove/bitswapStats/findProviders/findPeer/publishName/resolveName/listKeys` + `IpfsPeerInfo` / `IpfsBitswapStats` / `IpfsKeyInfo`
- SDK ui：`IpfsSwarmPanel`、`IpfsBootstrapPanel`、`IpfsBitswapPanel`、`IpfsDhtPanel`、`IpfsIpnsPanel`
- example 常用功能 tab 已集成全部面板
- 限制：IPNS 发布/解析依赖公网 DHT（离线不可用，测试以 `IPFS_PUBLIC_INTEGRATION=1` 门控）；bitswap 仅暴露接收侧块/字节计数与消息收发数（boxo v0.42 无发送侧块级计数）
