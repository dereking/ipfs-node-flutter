import { noise } from '@chainsafe/libp2p-noise'
import { yamux } from '@chainsafe/libp2p-yamux'
import { unixfs } from '@helia/unixfs'
import { circuitRelayTransport } from '@libp2p/circuit-relay-v2'
import { bootstrap } from '@libp2p/bootstrap'
import { identify } from '@libp2p/identify'
import { webRTC } from '@libp2p/webrtc'
import { webSockets } from '@libp2p/websockets'
import { webTransport } from '@libp2p/webtransport'
import { IDBBlockstore } from 'blockstore-idb'
import { createHelia } from 'helia'
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

class HeliaBrowserNode {
  #blockstore
  #helia
  #unixfs
  #libp2p
  #capabilities = []

  async start (bootstrapPeers = []) {
    if (this.#helia != null) return

    if (globalThis.indexedDB == null) {
      throw new Error('IndexedDB is required for persistent browser IPFS storage.')
    }

    const peers = bootstrapPeers.length === 0 ? publicBootstrapPeers : bootstrapPeers
    const transports = [webSockets(), circuitRelayTransport()]
    const capabilities = []
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
          identify: identify()
        },
        connectionEncrypters: [noise()],
        streamMuxers: [yamux()]
      })
      this.#helia = await createHelia({
        blockstore: this.#blockstore,
        libp2p: this.#libp2p
      })
      this.#unixfs = unixfs(this.#helia)
      this.#capabilities = capabilities
    } catch (error) {
      await this.#blockstore.close()
      this.#blockstore = undefined
      this.#libp2p = undefined
      throw error
    }
  }

  async stop () {
    if (this.#helia == null) return
    await this.#helia.stop()
    await this.#blockstore.close()
    this.#helia = undefined
    this.#unixfs = undefined
    this.#libp2p = undefined
    this.#blockstore = undefined
    this.#capabilities = []
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
    const chunks = []
    let length = 0
    for await (const chunk of this.#unixfs.cat(CID.parse(cid))) {
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

  #assertStarted () {
    if (this.#unixfs == null) {
      throw new Error('The browser IPFS node has not started.')
    }
  }
}
