import { noise } from '@chainsafe/libp2p-noise'
import { yamux } from '@chainsafe/libp2p-yamux'
import { unixfs } from '@helia/unixfs'
import { circuitRelayTransport } from '@libp2p/circuit-relay-v2'
import { webRTC } from '@libp2p/webrtc'
import { webSockets } from '@libp2p/websockets'
import { webTransport } from '@libp2p/webtransport'
import { IDBBlockstore } from 'blockstore-idb'
import { createHelia } from 'helia'
import { createLibp2p } from 'libp2p'
import { CID } from 'multiformats/cid'

const storeName = 'ipfs-node-flutter'

export async function create () {
  return new HeliaBrowserNode()
}

class HeliaBrowserNode {
  #blockstore
  #helia
  #unixfs
  #libp2p
  #capabilities = []

  async start () {
    if (this.#helia != null) return

    if (globalThis.indexedDB == null) {
      throw new Error('IndexedDB is required for persistent browser IPFS storage.')
    }

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
