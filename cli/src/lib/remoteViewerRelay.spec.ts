import { afterEach, expect, it } from 'vitest'
import { once } from 'node:events'
import { createServer, request } from 'node:http'
import type { AddressInfo } from 'node:net'
import { WebSocket, WebSocketServer } from 'ws'
import { BackendSocket, type Frame } from '../backendSocket.js'
import { attachLocalWsServer } from '../localWsServer.js'
import { env } from '../config/env.js'
import { DshViewerManager } from '../dsh/viewer.js'
import { E2eeStore } from './e2ee/store.js'
import { b64e, fingerprint, newIdentity } from './e2ee/core.js'
import { MachinePeerStore } from './e2ee/machinePeers.js'
import { RemoteRelayPool } from './remoteRelay.js'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { InstalledDsh } from '../dsh/installed.js'

const cleanup: Array<() => unknown | Promise<unknown>> = []
afterEach(async () => { for (const close of cleanup.splice(0).reverse()) await close() })

/** An opaque backend fixture: real sockets and production daemon handlers on both sides. */
it('desktop local-ws → relay → E2EE → daemon → spawned viewer, including restart and revocation', async () => {
  const machineId = 'a1234567890123456789012345678901a'
  const localIdentity = newIdentity()
  const remoteStore = new E2eeStore()
  const remoteIdentity = remoteStore.init()
  remoteStore.addPaired(b64e(localIdentity.pub), 'viewer e2e fixture', Date.now())
  const peers = new MachinePeerStore()
  peers.pin(machineId, b64e(remoteIdentity.pub), 'viewer e2e fixture')
  const relayServer = createServer()
  const relay = new WebSocketServer({ server: relayServer })
  let remote: WebSocket | undefined
  let client: WebSocket | undefined
  const encrypted: string[] = []
  relay.on('connection', (ws, req) => {
    if (req.url?.startsWith('/api/adapter-ws')) {
      remote = ws
      ws.on('message', (raw) => {
        const envelope = JSON.parse(raw.toString())
        if (envelope.t !== 'up') return
        if (String(envelope.frame.type).startsWith('viewer_')) encrypted.push(raw.toString())
        if (client?.readyState === WebSocket.OPEN) client.send(JSON.stringify(envelope.frame))
      })
    } else {
      client = ws
      ws.on('message', (raw) => {
        const frame = JSON.parse(raw.toString())
        if (frame.type === 'machine_select') { ws.send(JSON.stringify({ type: 'connected', payload: { machineId } })); return }
        if (String(frame.type).startsWith('viewer_')) encrypted.push(raw.toString())
        remote?.send(JSON.stringify({ t: 'down', connId: 'viewer-client', frame }))
      })
      ws.on('close', () => remote?.readyState === WebSocket.OPEN && remote.send(JSON.stringify({ t: 'down', connId: 'viewer-client', frame: { type: '__client_disconnected' } })))
    }
  })
  relayServer.listen(0, '127.0.0.1')
  await once(relayServer, 'listening')
  cleanup.push(() => { for (const ws of relay.clients) ws.terminate(); relay.close(); relayServer.close() })
  const base = `ws://127.0.0.1:${(relayServer.address() as AddressInfo).port}`
  const previousBase = env.BACKEND_WS_URL
  env.BACKEND_WS_URL = base
  cleanup.push(() => { env.BACKEND_WS_URL = previousBase })
  let connected!: () => void
  const online = new Promise<void>((resolve) => { connected = resolve })
  const daemon = new BackendSocket(machineId, undefined, (up) => { if (up) connected() })
  cleanup.push(() => daemon.stop())
  daemon.connect()
  await online

  const dir = mkdtempSync(join(tmpdir(), 'harness-viewer-e2e-'))
  cleanup.push(() => rmSync(dir, { recursive: true, force: true }))
  writeFileSync(join(dir, 'viewer.mjs'), `import http from 'node:http';
const server = http.createServer((req, res) => {
  if (req.url === '/events') { res.writeHead(200, {'Content-Type': 'text/event-stream'}); res.write('data: encrypted-live-output\\n\\n'); }
  else res.end('<html>encrypted-viewer-output<img src="/asset.svg"></html>');
});
server.listen(Number(process.env.HARNESS_VIEWER_PORT), '127.0.0.1');`)
  const manager = new DshViewerManager({
    onUrl: (agentId, viewerUrl) => {
      daemon.viewerForwarder.refresh(agentId)
      daemon.send({ type: 'agent_synced', payload: { agent: { id: agentId, viewerUrl, name: 'remote viewer fixture' } } })
    },
  })
  daemon.viewerTargetProvider = (agentId) => manager.forwardingUrl(agentId)
  cleanup.push(() => manager.stopAll())
  const dsh: InstalledDsh = {
    id: 'test/viewer', realDir: dir, dir, source: '', ref: null, commit: null, linked: false, installedAt: 0,
    manifest: { spec: 1, id: 'test/viewer', name: 'Viewer test', engine: 'claude', viewer: { command: `${JSON.stringify(process.execPath)} viewer.mjs`, url: 'http://127.0.0.1:${port}/?file=${artifact}' } },
  }

  const pool = new RemoteRelayPool({ accessToken: async () => 'fixture-token' } as never, base, localIdentity, peers)
  cleanup.push(() => pool.invalidate(machineId))
  const localServer = createServer()
  const localWs = attachLocalWsServer(localServer, { machineId: 'this-computer', backend: daemon, relayPool: pool, autonomousEnv: 'prod' })
  localServer.listen(0, '127.0.0.1')
  await once(localServer, 'listening')
  cleanup.push(async () => { await localWs.close(); localServer.close() })
  const desktop = new WebSocket(`ws://127.0.0.1:${(localServer.address() as AddressInfo).port}/api/local-ws`)
  cleanup.push(() => desktop.terminate())
  const frames: Frame[] = []
  desktop.on('message', (raw) => frames.push(JSON.parse(raw.toString())))
  async function until(predicate: () => boolean): Promise<void> {
    const deadline = Date.now() + 5000
    while (!predicate()) {
      if (Date.now() > deadline) throw new Error('E2E condition did not arrive')
      await new Promise((resolve) => setTimeout(resolve, 10))
    }
  }
  await once(desktop, 'open')
  desktop.send(JSON.stringify({ type: 'machine_select', payload: { machineId, localProtocolVersion: 1 } }))
  await until(() => frames.some((f) => f.type === 'connected'))
  await manager.start('agent', dsh, dir)
  const urls = () => frames.filter((f) => f.type === 'agent_synced').map((f) => (f.payload as any).agent.viewerUrl as string | null)
  await until(() => urls().some(Boolean))
  const url = urls().at(-1)!
  expect(new URL(url).origin).not.toBe(new URL(manager.url('agent')!).origin)
  const bootstrap = await fetch(url, { redirect: 'manual' })
  const cookie = bootstrap.headers.get('set-cookie')!.split(';')[0]
  const localOrigin = new URL(url).origin
  const page = await fetch(localOrigin + bootstrap.headers.get('location'), { headers: { cookie } })
  expect(await page.text()).toContain('encrypted-viewer-output')
  const live = await fetch(localOrigin + '/events', { headers: { cookie } })
  const reader = live.body!.getReader()
  expect(new TextDecoder().decode((await reader.read()).value)).toContain('encrypted-live-output')
  expect(encrypted.length).toBeGreaterThan(3)
  for (const raw of encrypted) {
    expect(raw).toContain('"__e2e"')
    expect(raw).not.toMatch(/encrypted-viewer-output|encrypted-live-output|"agentId"|"path"|"headers"|"data"/)
  }

  // Both incomplete streaming responses and the previous local origin die on a viewer restart.
  await manager.stop('agent')
  await expect(reader.read()).rejects.toThrow()
  await manager.start('agent', dsh, dir)
  await until(() => urls().at(-1) !== null && urls().at(-1) !== url)
  await expect(fetch(url)).rejects.toThrow()
  const restarted = urls().at(-1)!
  expect((await fetch(restarted, { redirect: 'manual' })).status).toBe(302)
  const ended = once(desktop, 'close')
  expect(daemon.revoke(fingerprint(localIdentity.pub)).ok).toBe(true)
  const [code] = await ended
  expect(code).toBe(4404)
  await expect(fetch(restarted)).rejects.toThrow()
  expect(peers.get(machineId)).toBeNull()
}, 20_000)
