import { noise } from '@chainsafe/libp2p-noise'
import { yamux } from '@chainsafe/libp2p-yamux'
import { withBitswap } from '@helia/bitswap'
import { ipns } from '@helia/ipns'
import { withLibp2p } from '@helia/libp2p'
import { unixfs } from '@helia/unixfs'
import { autoNAT } from '@libp2p/autonat'
import { bootstrap } from '@libp2p/bootstrap'
import { circuitRelayTransport } from '@libp2p/circuit-relay-v2'
import { dcutr } from '@libp2p/dcutr'
import { identify, identifyPush } from '@libp2p/identify'
import { kadDHT } from '@libp2p/kad-dht'
import { ping } from '@libp2p/ping'
import { webRTC } from '@libp2p/webrtc'
import { webSockets } from '@libp2p/websockets'
import { webTransport } from '@libp2p/webtransport'
import { IDBBlockstore } from 'blockstore-idb'
import { createHeliaLight } from 'helia'
import { createLibp2p } from 'libp2p'
import { CID } from 'multiformats/cid'

const storeName = 'ipfs-node-flutter'

// These are the WSS endpoints advertised by the public Amino DHT bootstrap
// peers.  Browsers cannot dial the TCP/QUIC addresses from the usual Kubo
// bootstrap list, but they can dial these TLS-secured WebSocket addresses.
// Callers can replace this list with their own browser-compatible bootstrap
// peers through PublicNodeConfig.bootstrapPeers.
const publicBootstrapPeers = [
  '/dns/sv15.bootstrap.libp2p.io/tcp/443/wss/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN',
  '/dns/sg1.bootstrap.libp2p.io/tcp/443/wss/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt',
  '/dns/ny5.bootstrap.libp2p.io/tcp/443/wss/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa',
  '/dns/am6.bootstrap.libp2p.io/tcp/443/wss/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb'
]

export function create () {
  return new HeliaBrowserNode()
}

// Keep Promise handling inside JavaScript. This avoids coupling Flutter's
// JS-interop runtime to a particular Promise implementation in the bundle.
export function start (node, peers, resolve, reject) {
  node.start(peers).then(resolve, error => reject(String(error)))
}

export function stop (node, resolve, reject) {
  node.stop().then(resolve, error => reject(String(error)))
}

export function capabilities (node, resolve, reject) {
  Promise.resolve(node.capabilities()).then(resolve, error => reject(String(error)))
}

export function addBytes (node, bytes, resolve, reject) {
  node.addBytes(bytes).then(resolve, error => reject(String(error)))
}

export function getBytes (node, cid, resolve, reject) {
  node.getBytes(cid).then(resolve, error => reject(String(error)))
}

export function pin (node, cid, resolve, reject) {
  node.pin(cid).then(resolve, error => reject(String(error)))
}

export function unpin (node, cid, resolve, reject) {
  node.unpin(cid).then(resolve, error => reject(String(error)))
}

export function listPins (node, resolve, reject) {
  node.listPins().then(resolve, error => reject(String(error)))
}

export function swarmPeers (node, resolve, reject) {
  node.swarmPeers().then(resolve, error => reject(String(error)))
}

export function bootstrapList (node, resolve, reject) {
  Promise.resolve(node.bootstrapList()).then(resolve, error => reject(String(error)))
}

export function bootstrapAdd (node, multiaddr, resolve, reject) {
  Promise.resolve(node.bootstrapAdd(multiaddr)).then(resolve, error => reject(String(error)))
}

export function bootstrapRemove (node, multiaddr, resolve, reject) {
  Promise.resolve(node.bootstrapRemove(multiaddr)).then(resolve, error => reject(String(error)))
}

export function findProviders (node, cid, timeoutMillis, resolve, reject) {
  node.findProviders(cid, timeoutMillis).then(resolve, error => reject(String(error)))
}

export function findPeer (node, peerId, timeoutMillis, resolve, reject) {
  node.findPeer(peerId, timeoutMillis).then(resolve, error => reject(String(error)))
}

export function publishName (node, cid, timeoutMillis, resolve, reject) {
  node.publishName(cid, timeoutMillis).then(resolve, error => reject(String(error)))
}

export function resolveName (node, name, timeoutMillis, resolve, reject) {
  node.resolveName(name, timeoutMillis).then(resolve, error => reject(String(error)))
}

export function listKeys (node, resolve, reject) {
  node.listKeys().then(resolve, error => reject(String(error)))
}

export function bitswapStats (node, resolve, reject) {
  Promise.resolve(node.bitswapStats()).then(resolve, error => reject(String(error)))
}

class HeliaBrowserNode {
  #blockstore
  #helia
  #unixfs
  #ipns
  #libp2p
  #bootstrap = []
  #capabilities = []
  #blocksSent = 0
  #blocksReceived = 0
  #dataSent = 0
  #dataReceived = 0
  #wants = new Set()

  async start (bootstrapPeers = []) {
    if (this.#helia != null) return

    if (globalThis.indexedDB == null) {
      throw new Error('IndexedDB is required for persistent browser IPFS storage.')
    }

    const peers = bootstrapPeers.length === 0 ? publicBootstrapPeers : bootstrapPeers
    this.#bootstrap = [...peers]
    const transports = [webSockets(), circuitRelayTransport()]
    const capabilities = ['dhtRouting']
    if (typeof globalThis.RTCPeerConnection === 'function') {
      transports.push(webRTC())
      capabilities.push('webRtc')
    }
    if (typeof globalThis.WebTransport === 'function') {
      transports.push(webTransport())
      capabilities.push('webTransport')
    }
    if (capabilities.length === 0) {
      throw new Error('This browser does not expose a supported libp2p transport.')
    }

    this.#blockstore = new IDBBlockstore(storeName)
    await this.#blockstore.open()
    try {
      this.#libp2p = await createLibp2p({
        transports,
        peerDiscovery: [bootstrap({ list: peers, timeout: 0, tagTTL: Infinity })],
        services: {
          autoNAT: autoNAT(),
          dcutr: dcutr(),
          dht: kadDHT({ clientMode: true }),
          identify: identify(),
          identifyPush: identifyPush(),
          ping: ping()
        },
        connectionEncrypters: [noise()],
        streamMuxers: [yamux()]
      })
      // Build Helia with our own libp2p (createHelia would build a fresh one and
      // ignore the browser transports above), then start it so the bitswap
      // block broker is created and the `libp2p` component (required by
      // @helia/ipns) becomes usable.
      this.#helia = withBitswap(withLibp2p(createHeliaLight({
        blockstore: this.#blockstore
      }), this.#libp2p))
      await this.#helia.start()
      this.#unixfs = unixfs(this.#helia)
      this.#ipns = ipns(this.#helia)
      this.#capabilities = capabilities
    } catch (error) {
      try {
        await this.#blockstore.close()
      } catch (_) {
        // Ignore close errors while unwinding a failed start.
      }
      this.#blockstore = undefined
      this.#libp2p = undefined
      this.#helia = undefined
      this.#unixfs = undefined
      this.#ipns = undefined
      throw error
    }
  }

  async stop () {
    if (this.#helia == null) return
    await this.#helia.stop()
    if (this.#blockstore != null) {
      await this.#blockstore.close()
    }
    this.#helia = undefined
    this.#unixfs = undefined
    this.#ipns = undefined
    this.#libp2p = undefined
    this.#blockstore = undefined
    this.#bootstrap = []
    this.#capabilities = []
    this.#blocksSent = 0
    this.#blocksReceived = 0
    this.#dataSent = 0
    this.#dataReceived = 0
    this.#wants = new Set()
  }

  capabilities () {
    return [...this.#capabilities]
  }

  async addBytes (bytes) {
    this.#assertStarted()
    return (await this.#unixfs.addBytes(bytes)).toString()
  }

  async getBytes (cid) {
    this.#assertStarted()
    const parsed = CID.parse(cid)
    this.#wants.add(cid)
    try {
      let bytes
      // Raw blocks (e.g. `bafkrei...`) are stored as-is; read the block from the
      // blockstore, which fetches missing blocks over the network when needed.
      if (parsed.code === 0x55) {
        bytes = await this.#collectBytes(this.#helia.blockstore.get(parsed))
      } else {
        // UnixFS files: stream the file content from the DAG.
        bytes = await this.#collectBytes(this.#unixfs.cat(parsed))
      }
      this.#blocksReceived += 1
      this.#dataReceived += bytes.byteLength
      return bytes
    } finally {
      this.#wants.delete(cid)
    }
  }

  async #collectBytes (source) {
    const chunks = []
    let length = 0
    for await (const chunk of source) {
      chunks.push(chunk)
      length += chunk.byteLength
    }
    const result = new Uint8Array(length)
    let offset = 0
    for (const chunk of chunks) {
      result.set(chunk, offset)
      offset += chunk.byteLength
    }
    return result
  }

  async pin (cid) {
    this.#assertStarted()
    for await (const _ of this.#helia.pins.add(CID.parse(cid))) {}
  }

  async unpin (cid) {
    this.#assertStarted()
    for await (const _ of this.#helia.pins.rm(CID.parse(cid))) {}
  }

  async listPins () {
    this.#assertStarted()
    const result = []
    for await (const pin of this.#helia.pins.ls()) {
      result.push({ cid: pin.cid.toString(), type: 'direct', pinnedAt: undefined })
    }
    return result
  }

  async swarmPeers () {
    this.#assertStarted()
    const result = []
    for (const connection of this.#libp2p.getConnections()) {
      result.push({
        id: connection.remotePeer.toString(),
        addrs: [connection.remoteAddr.toString()]
      })
    }
    return result
  }

  bootstrapList () {
    this.#assertStarted()
    return [...this.#bootstrap]
  }

  bootstrapAdd (multiaddr) {
    this.#assertStarted()
    if (!this.#bootstrap.includes(multiaddr)) {
      this.#bootstrap.push(multiaddr)
    }
  }

  bootstrapRemove (multiaddr) {
    this.#assertStarted()
    const index = this.#bootstrap.indexOf(multiaddr)
    if (index === -1) {
      throw new Error(`not a bootstrap peer: ${multiaddr}`)
    }
    this.#bootstrap.splice(index, 1)
  }

  async findProviders (cid, timeoutMillis) {
    this.#assertStarted()
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMillis)
    try {
      const result = []
      for await (const provider of this.#helia.routing.findProviders(CID.parse(cid), { signal: controller.signal })) {
        result.push({
          id: provider.id.toString(),
          addrs: (provider.multiaddrs ?? []).map(addr => addr.toString())
        })
      }
      return result
    } catch (error) {
      throw new Error(`find providers failed: ${error}`)
    } finally {
      clearTimeout(timer)
    }
  }

  async findPeer (peerId, timeoutMillis) {
    this.#assertStarted()
    if (peerId === this.#libp2p.peerId.toString()) {
      return {
        id: peerId,
        addrs: this.#libp2p.getMultiaddrs().map(addr => addr.toString())
      }
    }
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMillis)
    try {
      const peer = await this.#helia.routing.findPeer(CID.parse(peerId), { signal: controller.signal })
      if (peer == null) {
        return { id: peerId, addrs: [] }
      }
      return {
        id: peer.id.toString(),
        addrs: (peer.multiaddrs ?? []).map(addr => addr.toString())
      }
    } catch (error) {
      throw new Error(`find peer failed: ${error}`)
    } finally {
      clearTimeout(timer)
    }
  }

  async publishName (contentCID, timeoutMillis) {
    this.#assertStarted()
    const keyName = 'self'
    let found = false
    for await (const key of this.#helia.keychain.listKeys()) {
      if (key.name === keyName) {
        found = true
        break
      }
    }
    if (!found) {
      await this.#helia.keychain.generateKey(keyName)
    }
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMillis)
    try {
      const { publicKey } = await this.#ipns.publish(keyName, `/ipfs/${contentCID}`, { signal: controller.signal })
      return publicKey.toString()
    } catch (error) {
      throw new Error(`publish failed: ${error}`)
    } finally {
      clearTimeout(timer)
    }
  }

  async resolveName (rawName, timeoutMillis) {
    this.#assertStarted()
    const name = rawName.replace(/^\/ipns\//, '')
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMillis)
    try {
      let value = ''
      for await (const result of this.#ipns.resolve(CID.parse(name), { signal: controller.signal })) {
        value = result.value
      }
      if (value === '') {
        throw new Error(`no record found for ${rawName}`)
      }
      return value
    } catch (error) {
      throw new Error(`resolve failed: ${error}`)
    } finally {
      clearTimeout(timer)
    }
  }

  async listKeys () {
    this.#assertStarted()
    const result = []
    for await (const key of this.#helia.keychain.listKeys()) {
      result.push({ name: key.name, peerId: key.id })
    }
    return result
  }

  bitswapStats () {
    this.#assertStarted()
    return {
      blocksSent: this.#blocksSent,
      blocksReceived: this.#blocksReceived,
      dataSent: this.#dataSent,
      dataReceived: this.#dataReceived,
      wantlist: this.#wants.size,
      messagesSent: 0,
      messagesReceived: 0
    }
  }

  #assertStarted () {
    if (this.#unixfs == null) {
      throw new Error('The browser IPFS node has not started.')
    }
  }
}
