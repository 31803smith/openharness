import { describe, expect, it, vi } from 'vitest'
import type { WebSocket } from 'ws'

vi.mock('../utils/logger.js', () => ({ logger: { warn: vi.fn(), info: vi.fn(), error: vi.fn() } }))

const { guardedSend, guardedSendJson, SEND_HIGH_WATER, SEND_KILL_WATER } = await import('./wsSend.js')

function fakeSocket(bufferedAmount: number, readyState = 1) {
  const ws = {
    readyState,
    bufferedAmount,
    send: vi.fn(),
    close: vi.fn(),
    terminate: vi.fn(),
  }
  return ws as unknown as WebSocket & typeof ws
}

describe('guardedSend', () => {
  it('sends when the outbound buffer is small', () => {
    const ws = fakeSocket(0)
    expect(guardedSend(ws, 'x', 'droppable')).toBe(true)
    expect(ws.send).toHaveBeenCalledWith('x')
  })

  it('refuses a closed socket without touching it', () => {
    const ws = fakeSocket(0, 3)
    expect(guardedSend(ws, 'x', 'must')).toBe(false)
    expect(ws.send).not.toHaveBeenCalled()
  })

  it('drops droppable frames above the high-water mark but still sends must frames', () => {
    const ws = fakeSocket(SEND_HIGH_WATER + 1)
    expect(guardedSend(ws, 'out', 'droppable')).toBe(false)
    expect(ws.send).not.toHaveBeenCalled()
    expect(guardedSend(ws, 'delta', 'must')).toBe(true)
    expect(ws.send).toHaveBeenCalledWith('delta')
  })

  it('closes a slow consumer above the kill-water mark and terminates after the grace', () => {
    vi.useFakeTimers()
    try {
      const ws = fakeSocket(SEND_KILL_WATER + 1)
      expect(guardedSend(ws, 'x', 'must')).toBe(false)
      expect(ws.send).not.toHaveBeenCalled()
      expect(ws.close).toHaveBeenCalledWith(1013, 'slow consumer')
      expect(ws.terminate).not.toHaveBeenCalled()
      vi.advanceTimersByTime(2_000)
      expect(ws.terminate).toHaveBeenCalled()
    } finally {
      vi.useRealTimers()
    }
  })

  it('does not terminate a socket that finished closing on its own', () => {
    vi.useFakeTimers()
    try {
      const ws = fakeSocket(SEND_KILL_WATER + 1)
      guardedSend(ws, 'x', 'must')
      ws.readyState = 3 // CLOSED before the grace elapses
      vi.advanceTimersByTime(2_000)
      expect(ws.terminate).not.toHaveBeenCalled()
    } finally {
      vi.useRealTimers()
    }
  })

  it('guardedSendJson serializes and defaults to must', () => {
    const ws = fakeSocket(SEND_HIGH_WATER + 1)
    expect(guardedSendJson(ws, { type: 'node_status' })).toBe(true)
    expect(ws.send).toHaveBeenCalledWith('{"type":"node_status"}')
  })
})
