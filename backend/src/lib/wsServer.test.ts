import { describe, expect, it, vi } from 'vitest'

// A minimal fake WebSocketServer so createWss's `wss.on('connection', …)` wiring is observable
// without a real network handshake.
const hoisted = vi.hoisted(() => ({ servers: [] as Array<{ handlers: Record<string, Function[]>; clients: Set<unknown> }> }))
vi.mock('ws', () => {
  class FakeWss {
    handlers: Record<string, Function[]> = {}
    clients = new Set<unknown>()
    constructor(_opts: unknown) { hoisted.servers.push(this) }
    on(event: string, cb: Function) { (this.handlers[event] ??= []).push(cb); return this }
    emit(event: string, ...args: unknown[]) { for (const cb of this.handlers[event] ?? []) cb(...args) }
  }
  return { WebSocketServer: FakeWss }
})

const { createWss, RELEASE_UPGRADE_SLOT } = await import('./wsServer.js')

describe('createWss upgrade-slot release', () => {
  it('calls the raw socket’s release hook on a successful connection', () => {
    const wss = createWss(1024) as unknown as { emit: (e: string, ...a: unknown[]) => void }
    const release = vi.fn()
    const rawSocket: Record<PropertyKey, unknown> = { [RELEASE_UPGRADE_SLOT]: release }
    // ws emits 'connection' with the WebSocket; createWss reaches its ._socket.
    wss.emit('connection', { _socket: rawSocket })
    expect(release).toHaveBeenCalledTimes(1)
  })

  it('is a no-op for a socket that carries no release hook (e.g. the app-proxy)', () => {
    const wss = createWss(1024) as unknown as { emit: (e: string, ...a: unknown[]) => void }
    expect(() => wss.emit('connection', { _socket: {} })).not.toThrow()
    expect(() => wss.emit('connection', {})).not.toThrow()
  })
})
