/**
 * Liveness for a WebSocket this daemon holds — a DEADLINE ON SILENCE, not "one missed pong".
 *
 * Three sockets used to carry three copies of the same heartbeat, each pinging every 20s and
 * terminating the moment the previous ping had no pong — and counting pongs only. Two failure modes
 * followed, both measured in harness.log as `close 1006`:
 *   - a peer busy streaming data frames whose control-frame pong arrived late lost a working link;
 *   - every macOS DarkWake (Power Nap, ~5–10s of wake) fired the timer with the pre-sleep ping still
 *     unanswered and terminated on the spot, hundreds of times a week, with no chance to recover.
 *
 * Here ANY inbound frame proves the peer — data, its own ping, a pong — and the socket is only given
 * up after `WS_IDLE_DEADLINE_MS` of nothing at all: three pings' worth, the same shape the backend's
 * `trackSocketLiveness` applies from its side (75s there). Silence is measured on the MONOTONIC clock
 * (`performance.now()` does not advance while the machine sleeps), so the deadline is sixty seconds of
 * silence while awake — a lid closed for an hour is not an hour of silence, and the link gets its
 * three pings after the wake before anyone gives up on it.
 */

import type { WebSocket } from 'ws'

export const WS_HEARTBEAT_MS = 20_000
export const WS_IDLE_DEADLINE_MS = 60_000

export interface LivenessWatch {
  /** Stop pinging and judging. Idempotent; the socket itself is left alone. */
  stop(): void
}

export interface LivenessOptions {
  heartbeatMs?: number
  deadlineMs?: number
  /** Runs on every heartbeat tick the socket survives — for work that rides the same cadence. */
  onTick?: () => void
  /** Announced right before a silent socket is terminated, so a later trace can tell "we gave up"
   *  from "the network did": both close as 1006, and only this one is said out loud first. */
  onIdle?: (idleMs: number) => void
}

/** Start watching an OPEN socket. Call once the handshake is done — the clock starts now. */
export function watchSocketLiveness(ws: WebSocket, opts: LivenessOptions = {}): LivenessWatch {
  const deadlineMs = opts.deadlineMs ?? WS_IDLE_DEADLINE_MS
  let lastAliveAt = performance.now()
  const markAlive = (): void => { lastAliveAt = performance.now() }
  ws.on('pong', markAlive)
  ws.on('ping', markAlive) // the peer's own liveness ping — a proof that costs nothing
  ws.on('message', markAlive) // data flowing is the strongest proof there is
  // Judging ends with the verdict: the socket's own 'close' is what the owner cleans up on, and a
  // watch that kept firing after its terminate would only terminate a dead socket again.
  const stop = (): void => { clearInterval(timer) }
  const giveUp = (): void => {
    stop()
    try { ws.terminate() } catch { /* ignore */ }
  }
  // Belt and suspenders for an owner that forgets: `ws.ping()` on a closed socket does not throw
  // (it is silently dropped), so an unstopped watch would tick against a corpse forever.
  ws.once('close', stop)
  const timer = setInterval(() => {
    const idleMs = performance.now() - lastAliveAt
    if (idleMs >= deadlineMs) {
      opts.onIdle?.(idleMs)
      giveUp()
      return
    }
    // A ping that cannot even be written means the socket is already gone under us.
    try { ws.ping() } catch { giveUp(); return }
    opts.onTick?.()
  }, opts.heartbeatMs ?? WS_HEARTBEAT_MS)
  timer.unref?.()
  return { stop }
}
