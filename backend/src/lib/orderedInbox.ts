/**
 * Strict in-order processing of inbound frames, with a ceiling.
 *
 * The web and device endpoints must handle frames one at a time in arrival order (a `machine_select`
 * followed by an RPC must not be routed by the previous selection). That was a promise chain — but a
 * chain has no ceiling, and one link can legitimately wait a long time (`ensureMachineReady` blocks up
 * to ~190s while a stopped machine provisions). Everything a client sent meanwhile sat in the heap, with
 * nothing to stop it: a client can push thousands of RPCs per minute inside the rate guards.
 *
 * Deliberately NOT `ws.pause()`: pausing the socket also stops reading ping/pong control frames, so the
 * liveness sweep would kill a healthy client (and the ESP32 firmware expects its own pings answered).
 * Instead, past `maxInflight` a frame is refused via `onOverflow` — the caller answers it immediately
 * (fast-fail the RPC / error frame) so the client is not left waiting on something that will never run.
 */
export interface OrderedInboxOptions {
  maxInflight?: number
}

export const DEFAULT_MAX_INFLIGHT = 256

export interface OrderedInbox<T> {
  /** Queue a frame. Returns false when it was refused (overflow) — `onOverflow` has already been called. */
  enqueue: (frame: T) => boolean
  /** Frames queued or running right now. */
  inflight: () => number
}

export function createOrderedInbox<T>(
  handle: (frame: T) => Promise<void>,
  onError: (err: unknown, frame: T) => void,
  onOverflow: (frame: T, inflight: number) => void,
  opts: OrderedInboxOptions = {},
): OrderedInbox<T> {
  const maxInflight = opts.maxInflight ?? DEFAULT_MAX_INFLIGHT
  let chain: Promise<void> = Promise.resolve()
  let inflight = 0
  return {
    enqueue: (frame: T): boolean => {
      if (inflight >= maxInflight) {
        onOverflow(frame, inflight)
        return false
      }
      inflight++
      chain = chain
        .then(() => handle(frame))
        .catch((err) => onError(err, frame))
        .finally(() => { inflight-- })
      return true
    },
    inflight: () => inflight,
  }
}
