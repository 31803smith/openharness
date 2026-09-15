import { afterEach, describe, expect, it, vi } from 'vitest'
import { EventEmitter } from 'node:events'
import type { WebSocket } from 'ws'
import { watchSocketLiveness, WS_HEARTBEAT_MS, WS_IDLE_DEADLINE_MS } from './wsLiveness.js'

class FakeSocket extends EventEmitter {
  pings = 0
  terminated = 0
  /** Peer stopped answering (half-open TCP, a laptop back from sleep). */
  silent = false
  pingThrows = false
  ping(): void {
    if (this.pingThrows) throw new Error('not open')
    this.pings++
    if (!this.silent) this.emit('pong')
  }
  terminate(): void { this.terminated++ }
}

const socket = () => new FakeSocket() as unknown as WebSocket & FakeSocket

afterEach(() => { vi.useRealTimers() })

describe('watchSocketLiveness', () => {
  it('keeps a responsive socket alive indefinitely, pinging on the heartbeat', async () => {
    vi.useFakeTimers()
    const ws = socket()
    watchSocketLiveness(ws)
    await vi.advanceTimersByTimeAsync(WS_HEARTBEAT_MS * 10)
    expect(ws.pings).toBe(10)
    expect(ws.terminated).toBe(0)
  })

  it('gives a silent peer the whole deadline — three pings — not one missed pong', async () => {
    vi.useFakeTimers()
    const ws = socket()
    ws.silent = true
    const idle: number[] = []
    watchSocketLiveness(ws, { onIdle: (ms) => idle.push(ms) })
    await vi.advanceTimersByTimeAsync(WS_IDLE_DEADLINE_MS - 1)
    expect(ws.terminated).toBe(0)
    expect(ws.pings).toBe(2)
    await vi.advanceTimersByTimeAsync(WS_HEARTBEAT_MS)
    expect(ws.terminated).toBe(1)
    expect(idle).toEqual([WS_IDLE_DEADLINE_MS])
  })

  it('counts data and the peer\'s own pings as proof of life, not only pongs', async () => {
    vi.useFakeTimers()
    const ws = socket()
    ws.silent = true
    watchSocketLiveness(ws)
    await vi.advanceTimersByTimeAsync(40_000)
    ws.emit('message', Buffer.from('{}'))
    await vi.advanceTimersByTimeAsync(40_000)
    expect(ws.terminated).toBe(0)
    ws.emit('ping')
    await vi.advanceTimersByTimeAsync(40_000)
    expect(ws.terminated).toBe(0)
    await vi.advanceTimersByTimeAsync(WS_IDLE_DEADLINE_MS)
    expect(ws.terminated).toBe(1)
  })

  it('runs the piggybacked tick only on a surviving socket, and stops cleanly', async () => {
    vi.useFakeTimers()
    const ws = socket()
    ws.silent = true
    let ticks = 0
    const watch = watchSocketLiveness(ws, { onTick: () => { ticks++ } })
    await vi.advanceTimersByTimeAsync(WS_HEARTBEAT_MS * 2)
    expect(ticks).toBe(2)
    await vi.advanceTimersByTimeAsync(WS_HEARTBEAT_MS)
    expect(ws.terminated).toBe(1)
    expect(ticks).toBe(2) // the terminating tick does no other work
    watch.stop()
    await vi.advanceTimersByTimeAsync(WS_HEARTBEAT_MS * 5)
    expect(ws.terminated).toBe(1)
  })

  it('stops by itself when the socket closes, whether or not the owner remembered to', async () => {
    vi.useFakeTimers()
    const ws = socket()
    watchSocketLiveness(ws)
    await vi.advanceTimersByTimeAsync(WS_HEARTBEAT_MS)
    expect(ws.pings).toBe(1)
    ws.emit('close', 1000)
    await vi.advanceTimersByTimeAsync(WS_HEARTBEAT_MS * 5)
    expect(ws.pings).toBe(1)
  })

  it('terminates a socket it cannot even ping', async () => {
    vi.useFakeTimers()
    const ws = socket()
    ws.pingThrows = true
    watchSocketLiveness(ws)
    await vi.advanceTimersByTimeAsync(WS_HEARTBEAT_MS)
    expect(ws.terminated).toBe(1)
  })
})
