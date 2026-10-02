// Originally written by Fred Nix (@nixfred) in github.com/nixfred/openharness (MIT), where it was
// `nixfredWiring.ts`. Ported here without the device firmware frames, Orca watch mode or Hermes parts.

/**
 * The fleet controls, wired as one object the daemon calls at a handful of points. Everything here is
 * built from pure modules (lib/attention, ...) so the daemon's own files change as little as possible:
 *
 *   attention   turn/question/cancel taps → `attention` frames to local windows, `GET /api/attention`
 *   stop-all    cancel every agent turn on this machine (`POST /api/stop-all`, `harness stop-all`)
 *   commands    the `harness <command>` local API behind `POST /api/fleet`
 */
import { mkdirSync } from 'node:fs'
import { env } from '../config/env.js'
import { AttentionTracker, summarizeAttention, type AttentionRow } from '../lib/attention.js'

export interface FleetSessionLike {
  agentId: string
  sessionId: string
  engine: string
  active: boolean
  tmuxPane?: string
  cwd?: string
  transcriptPath?: string
  model?: string | null
  name: string
}

export interface FleetControlDeps {
  dataDir?: string
  machineId: () => string
  machineName: () => string
  sessions: () => FleetSessionLike[]
  /** Push a frame to every local window (desktop). */
  sendLocal: (frame: { type: string; payload: Record<string, unknown> }) => void
  cancelAgent: (agentId: string, confirmed: boolean) => Promise<boolean>
  now?: () => number
}

export class FleetControl {
  readonly attention: AttentionTracker
  protected readonly dataDir: string
  protected readonly now: () => number

  constructor(protected readonly deps: FleetControlDeps) {
    this.now = deps.now ?? Date.now
    this.dataDir = deps.dataDir ?? env.ADAPTER_DATA_DIR
    mkdirSync(this.dataDir, { recursive: true })
    this.attention = new AttentionTracker(this.now)
    this.attention.onChange(() => this.pushAttention())
  }

  // ── attention ───────────────────────────────────────────────────────────────────────────────────

  snapshot(): AttentionRow[] { return this.attention.snapshot(this.deps.sessions(), this.deps.machineName()) }

  attentionPayload(): Record<string, unknown> {
    const agents = this.snapshot()
    return { machineId: this.deps.machineId(), hostname: this.deps.machineName(), at: this.now(), summary: summarizeAttention(agents), agents }
  }

  /** Every local window hears each real transition; the bar widget polls `GET /api/attention` instead. */
  protected pushAttention(): void {
    this.deps.sendLocal({ type: 'attention', payload: this.attentionPayload() })
  }

  // ── panic stop ─────────────────────────────────────────────────────────────────────────────────

  async stopAll(exceptAgentId: string | null): Promise<{ cancelled: string[] }> {
    const cancelled: string[] = []
    for (const s of this.deps.sessions()) {
      if (!s.active || s.agentId === exceptAgentId) continue
      try { if (await this.deps.cancelAgent(s.agentId, true)) cancelled.push(s.agentId) } catch { /* next */ }
      this.attention.cancelled(s.agentId)
    }
    console.log(`[fleet] panic stop: cancelled ${cancelled.length} agent(s), kept ${exceptAgentId ?? 'none'}`)
    return { cancelled }
  }

  // ── the local command surface (`POST /api/fleet`) ──────────────────────────────────────────────

  async command(action: string, args: Record<string, unknown>): Promise<unknown> {
    const str = (k: string): string => (typeof args[k] === 'string' ? args[k] as string : '')
    switch (action) {
      case 'attention': return this.attentionPayload()
      case 'stop-all': return this.stopAll(str('except') || null)
      default: throw new Error(`unknown fleet action: ${action}`)
    }
  }
}

export type { AttentionRow }
