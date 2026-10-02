// Originally written by Fred Nix (@nixfred) in github.com/nixfred/openharness (MIT), where it was
// `nixfredWiring.ts`. Ported here without the device firmware frames, Orca watch mode or Hermes parts.

/**
 * The fleet controls, wired as one object the daemon calls at a handful of points. Everything here is
 * built from pure modules (lib/attention, ...) so the daemon's own files change as little as possible:
 *
 *   attention   turn/question/cancel taps → `attention` frames to local windows, `GET /api/attention`
 *   stop-all    cancel every agent turn on this machine (`POST /api/stop-all`, `harness stop-all`)
 *   gate        tool-start → policy verdict (Claude PreToolUse permissionDecision), `harness gate`
 *   spend       submit → pause when caps are hit; ledger persisted per day, `harness spend`
 *   commands    the `harness <command>` local API behind `POST /api/fleet`
 */
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { env } from '../config/env.js'
import { AttentionTracker, summarizeAttention, type AttentionRow } from '../lib/attention.js'
import { DEFAULT_POLICY, evaluateToolCall, parsePolicy, type ActionPolicy, type GateVerdict } from '../lib/actionPolicy.js'
import { DEFAULT_CAPS, decideSpend, emptyLedger, parseCaps, recordUsage, type BrakeVerdict, type SpendCaps, type SpendLedger } from '../lib/spendBrake.js'
import { gateHookInstalled, installGateHook, uninstallGateHook } from '../lib/hooks.js'

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
  /** Push an error message frame to the web for one agent. */
  sendError: (agentId: string, sessionId: string, message: string) => void
  cancelAgent: (agentId: string, confirmed: boolean) => Promise<boolean>
  tokenUsage: (s: FleetSessionLike) => { totalTokens: number | null } | null
  hookPort: () => number
  now?: () => number
}

function readJson<T>(file: string): T | null {
  try { return JSON.parse(readFileSync(file, 'utf8')) as T } catch { return null }
}
function writeJson(file: string, value: unknown): void {
  mkdirSync(join(file, '..'), { recursive: true })
  const tmp = `${file}.${process.pid}.tmp`
  writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n')
  renameSync(tmp, file)
}

export class FleetControl {
  readonly attention: AttentionTracker
  protected readonly dataDir: string
  protected readonly now: () => number
  private policy: ActionPolicy
  private caps: SpendCaps
  private ledger: SpendLedger

  constructor(protected readonly deps: FleetControlDeps) {
    this.now = deps.now ?? Date.now
    this.dataDir = deps.dataDir ?? env.ADAPTER_DATA_DIR
    mkdirSync(this.dataDir, { recursive: true })
    this.attention = new AttentionTracker(this.now)
    this.policy = this.loadPolicy()
    this.caps = this.loadCaps()
    this.ledger = readJson<SpendLedger>(this.file('spend-ledger.json')) ?? emptyLedger(this.now())
    this.attention.onChange(() => this.pushAttention())
  }

  protected file(name: string): string { return join(this.dataDir, name) }

  // ── attention ───────────────────────────────────────────────────────────────────────────────────

  snapshot(): AttentionRow[] { return this.attention.snapshot(this.deps.sessions(), this.deps.machineName()) }

  attentionPayload(): Record<string, unknown> {
    // Each agent carries the name of the first policy lane its name matches (planner, publisher ...),
    // so the bar can show the role beside the state.
    const lanes = this.policy.lanes ?? []
    const agents = this.snapshot().map((row) => {
      const spent = this.ledger.agents[row.agentId]
      const cap = this.caps.enabled ? this.caps.perAgentUsd : null
      // Spend rides on the row so the bar can draw it as the ring's outer arc: fraction of the
      // per-agent cap when one is set, else null (no arc).
      const spend = spent ? { usd: Number(spent.usd.toFixed(2)), tokens: spent.input + spent.output, fraction: cap ? Math.min(1.5, spent.usd / cap) : null } : null
      return { ...row, lane: lanes.find((l) => { try { return new RegExp(l.agent, 'i').test(row.name) } catch { return false } })?.name ?? null, spend }
    })
    return { machineId: this.deps.machineId(), hostname: this.deps.machineName(), at: this.now(), summary: summarizeAttention(agents), agents }
  }

  /** Every local window hears each real transition; the bar widget polls `GET /api/attention` instead. */
  protected pushAttention(): void {
    this.deps.sendLocal({ type: 'attention', payload: this.attentionPayload() })
  }

  // ── gate ────────────────────────────────────────────────────────────────────────────────────────

  private loadPolicy(): ActionPolicy {
    const raw = readJson<unknown>(this.file('action-policy.json'))
    if (raw === null) return DEFAULT_POLICY
    const parsed = parsePolicy(raw)
    if (parsed.ok) return parsed.policy
    console.error(`[gate] action-policy.json ignored: ${parsed.problems.join('; ')}`)
    return DEFAULT_POLICY
  }

  /** A tool call is about to run: classify it. Only reached when `harness gate install` added the hook. */
  gate(sessionId: string, agentId: string, toolName: string, input: unknown): GateVerdict {
    const agentName = this.deps.sessions().find((s) => s.agentId === agentId)?.name ?? ''
    const verdict = evaluateToolCall(this.policy, toolName, input, agentName)
    if (verdict.decision !== 'allow') {
      console.log(`[gate] ${agentId} ${sessionId} ${toolName} → ${verdict.decision} (${verdict.rule})`)
      if (verdict.decision === 'ask') this.attention.question(agentId, true, verdict.reason)
    }
    return verdict
  }

  gateStatus(): Record<string, unknown> {
    return { installed: gateHookInstalled(), enabled: this.policy.enabled, rules: this.policy.rules.length, file: this.file('action-policy.json'), fileExists: existsSync(this.file('action-policy.json')) }
  }

  gateInit(): string { const f = this.file('action-policy.json'); if (!existsSync(f)) writeJson(f, DEFAULT_POLICY); this.policy = this.loadPolicy(); return f }

  // ── spend ───────────────────────────────────────────────────────────────────────────────────────

  private loadCaps(): SpendCaps {
    const raw = readJson<unknown>(this.file('spend-caps.json'))
    if (raw === null) return DEFAULT_CAPS
    const parsed = parseCaps(raw)
    if (parsed.ok) return parsed.caps
    console.error(`[spend] spend-caps.json ignored: ${parsed.problems.join('; ')}`)
    return DEFAULT_CAPS
  }

  /** Record what this agent has used so far, then decide whether its next turn may run. */
  spendCheck(s: FleetSessionLike): BrakeVerdict {
    const usage = this.deps.tokenUsage(s)
    const total = usage?.totalTokens ?? 0
    // The engines report a total; treat a fifth as output, which is where most of the money goes.
    this.ledger = recordUsage(this.ledger, { agentId: s.agentId, model: s.model ?? null, input: Math.round(total * 0.8), output: Math.round(total * 0.2), now: this.now() })
    writeJson(this.file('spend-ledger.json'), this.ledger)
    const verdict = decideSpend(this.caps, this.ledger, s.agentId)
    if (verdict.action !== 'run') console.log(`[spend] ${s.agentId} ${verdict.action}: ${verdict.reason}`)
    if (verdict.action === 'pause') {
      this.attention.question(s.agentId, false, `spend brake: ${verdict.reason}`)
      this.deps.sendError(s.agentId, s.sessionId, `Spend brake ${verdict.reason}. Raise the cap with "harness spend set" to continue.`)
    }
    return verdict
  }

  spendStatus(): Record<string, unknown> {
    return { caps: this.caps, day: this.ledger.day, agents: Object.values(this.ledger.agents).map((a) => ({ agentId: a.agentId, model: a.model, tokens: a.input + a.output, usd: Number(a.usd.toFixed(4)) })) }
  }

  spendSet(patch: Partial<SpendCaps>): SpendCaps {
    // Setting a cap is asking for the brake: the default is off (subscription users pay no list price).
    const setsCap = ['perAgentUsd', 'perAgentTokens', 'perDayUsd', 'perDayTokens'].some((k) => typeof (patch as Record<string, unknown>)[k] === 'number')
    const next = { ...this.caps, ...(setsCap && patch.enabled === undefined ? { enabled: true } : {}), ...patch, version: 1 as const }
    const parsed = parseCaps(next)
    if (!parsed.ok) throw new Error(parsed.problems.join('; '))
    this.caps = parsed.caps
    writeJson(this.file('spend-caps.json'), this.caps)
    return this.caps
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
      case 'gate-status': return this.gateStatus()
      case 'gate-init': return { file: this.gateInit() }
      case 'gate-install': return { result: installGateHook(this.deps.hookPort()), ...this.gateStatus() }
      case 'gate-uninstall': return { result: uninstallGateHook(), ...this.gateStatus() }
      case 'gate-reload': this.policy = this.loadPolicy(); return this.gateStatus()
      case 'spend-status': return this.spendStatus()
      case 'spend-set': {
        const patch: Partial<SpendCaps> = {}
        for (const k of ['perAgentUsd', 'perAgentTokens', 'perDayUsd', 'perDayTokens', 'warnAt'] as const) {
          if (args[k] === null) patch[k] = null as never
          else if (typeof args[k] === 'number') patch[k] = args[k] as never
        }
        if (typeof args.enabled === 'boolean') patch.enabled = args.enabled
        return { caps: this.spendSet(patch) }
      }
      default: throw new Error(`unknown fleet action: ${action}`)
    }
  }
}

export type { AttentionRow, GateVerdict, BrakeVerdict }
