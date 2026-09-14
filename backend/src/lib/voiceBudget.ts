/**
 * Process-wide budget for voice PCM buffered ahead of STT. Every device socket may hold up to
 * `MAX_PCM` (20 MiB) for one utterance, and `finishVoice` briefly holds a second copy (`Buffer.concat`);
 * with nothing above the per-socket cap, "many devices recording at once" was a straight path to the
 * OOM-killer taking a whole cluster worker — and every socket on it — instead of one upload failing.
 */
import { env } from '../config/env.js'

let inflightBytes = 0

/** Take `bytes` from the budget. Returns false (and takes nothing) when it would exceed the cap. */
export function reserveVoice(bytes: number): boolean {
  if (bytes <= 0) return true
  if (inflightBytes + bytes > env.VOICE_INFLIGHT_MAX_BYTES) return false
  inflightBytes += bytes
  return true
}

/** Give `bytes` back. Clamped at zero so a double release can never grant more than the cap. */
export function releaseVoice(bytes: number): void {
  if (bytes <= 0) return
  inflightBytes = Math.max(0, inflightBytes - bytes)
}

export function voiceInflightBytes(): number {
  return inflightBytes
}
