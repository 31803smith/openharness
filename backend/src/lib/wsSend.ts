/**
 * Outbound send with backpressure. `ws.send()` never blocks and never drops: whatever the peer does not
 * read piles up in this process' heap (`bufferedAmount`). A browser tab throttled in the background, or
 * a peer behind a small TCP window, while an agent streams turn deltas / terminal output, therefore grew
 * memory linearly with stream rate — and the liveness sweep could not catch it, because that measures
 * INBOUND silence and a slow reader still answers pings.
 *
 * Two thresholds, one policy per frame:
 *   - over SEND_HIGH_WATER a `droppable` frame is skipped. A frame is only droppable when losing it is
 *     invisible to the client — a full-snapshot frame that a later one supersedes. It is NOT for
 *     order-sensitive streams (chat deltas) or opaque byte streams (terminal output has no per-frame ack,
 *     so a dropped frame is an undetectable gap that stalls the pane); those ride until the kill line.
 *   - over SEND_KILL_WATER the peer is declared a slow consumer and closed (1013 = try again later, the
 *     client's reconnect backoff handles it). `terminate()` follows shortly, since a peer that is not
 *     reading is unlikely to complete the close handshake either. This close is what bounds memory for
 *     `must` frames.
 */
import { WebSocket } from 'ws'
import { logger } from '../utils/logger.js'

export const SEND_HIGH_WATER = 2 * 1024 * 1024
export const SEND_KILL_WATER = 8 * 1024 * 1024
const SLOW_CONSUMER_TERMINATE_MS = 2_000

export type SendPolicy = 'must' | 'droppable'

let droppedFrames = 0
let slowConsumerCloses = 0

/** Counters for diagnostics / a future metrics endpoint. */
export function sendStats(): { droppedFrames: number; slowConsumerCloses: number } {
  return { droppedFrames, slowConsumerCloses }
}

/** Returns true when the frame was handed to `ws`; false when skipped, dropped, or the socket was closed. */
export function guardedSend(ws: WebSocket, data: string | Uint8Array, policy: SendPolicy, info?: Record<string, unknown>): boolean {
  if (ws.readyState !== WebSocket.OPEN) return false
  const buffered = ws.bufferedAmount
  if (buffered > SEND_KILL_WATER) {
    slowConsumerCloses++
    logger.warn('ws slow consumer — closing', { ...info, buffered })
    try { ws.close(1013, 'slow consumer') } catch { /* ignore */ }
    setTimeout(() => {
      if (ws.readyState !== WebSocket.CLOSED) { try { ws.terminate() } catch { /* ignore */ } }
    }, SLOW_CONSUMER_TERMINATE_MS).unref?.()
    return false
  }
  if (policy === 'droppable' && buffered > SEND_HIGH_WATER) {
    droppedFrames++
    return false
  }
  try { ws.send(data); return true } catch { return false }
}

/** JSON convenience over guardedSend. */
export function guardedSendJson(ws: WebSocket, obj: unknown, policy: SendPolicy = 'must', info?: Record<string, unknown>): boolean {
  return guardedSend(ws, JSON.stringify(obj), policy, info)
}
