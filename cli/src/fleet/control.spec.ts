// Originally written by Fred Nix (@nixfred) in github.com/nixfred/openharness (MIT), as nixfredWiring.spec.ts.

import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { FleetControl, type FleetControlDeps, type FleetSessionLike } from './control.js'

vi.mock('../lib/hooks.js', () => ({ installGateHook: () => 'installed', uninstallGateHook: () => 'removed', gateHookInstalled: () => false }))

const session = (agentId: string, extra: Partial<FleetSessionLike> = {}): FleetSessionLike => ({
  agentId, sessionId: `s-${agentId}`, engine: 'claude', active: true, tmuxPane: '%3', cwd: '/tmp/proj', name: agentId, model: 'claude-sonnet', ...extra,
})

describe('FleetControl', () => {
  let dir: string
  let sent: Array<{ type: string; payload: Record<string, unknown> }>
  let cancelled: string[]
  let errors: string[]
  let sessions: FleetSessionLike[]
  let tokens: number
  let fleet: FleetControl
  let now: number

  const deps = (): FleetControlDeps => ({
    dataDir: dir,
    machineId: () => 'm-1',
    machineName: () => 'gus',
    sessions: () => sessions,
    sendLocal: (f) => { sent.push(f) },
    sendError: (_a, _s, m) => { errors.push(m) },
    cancelAgent: async (id) => { cancelled.push(id); return true },
    tokenUsage: () => ({ totalTokens: tokens }),
    hookPort: () => 18473,
    now: () => now,
  })

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'fleet-'))
    sent = []; cancelled = []; errors = []; tokens = 0; now = Date.UTC(2026, 8, 26, 16, 0)
    sessions = [session('a'), session('b')]
    fleet = new FleetControl(deps())
  })
  afterEach(() => { rmSync(dir, { recursive: true, force: true }) })

  it('turns attention changes into a local frame with a summary and glyphs', () => {
    fleet.attention.turnStarted('a', 'fix login')
    fleet.attention.question('b', true, 'Bash: git push')
    const last = sent.at(-1)!
    expect(last.type).toBe('attention')
    const p = last.payload as { hostname: string; summary: { state: string; agentId: string }; agents: Array<{ agentId: string; state: string; glyph: string }> }
    expect(p.hostname).toBe('gus')
    expect(p.summary).toMatchObject({ state: 'permission', agentId: 'b' })
    expect(p.agents.map((a) => `${a.agentId}:${a.state}:${a.glyph}`)).toEqual(['b:permission:!', 'a:working:~'])
  })

  it('gate asks on a push, allows a plain command, and marks the agent as needing permission', () => {
    expect(fleet.gate('s-a', 'a', 'Bash', { command: 'git status' }).decision).toBe('allow')
    const v = fleet.gate('s-a', 'a', 'Bash', { command: 'git push origin main' })
    expect(v).toMatchObject({ decision: 'ask', rule: 'git push' })
    expect(fleet.attention.get('a')?.state).toBe('permission')
  })

  it('spend brake pauses the pane once the per-agent cap is hit and tells the web', () => {
    fleet.spendSet({ perAgentUsd: 1, perDayUsd: null })
    tokens = 100_000
    expect(fleet.spendCheck(session('a')).action).toBe('run')
    tokens = 400_000 // sonnet: 320k in * 3 + 80k out * 15 per M = 0.96 + 1.2 = 2.16 USD
    const v = fleet.spendCheck(session('a'))
    expect(v.action).toBe('pause')
    expect(errors[0]).toMatch(/Spend brake paused: agent at \$2\.16 of \$1/)
    expect(fleet.attention.get('a')).toMatchObject({ state: 'waiting' })
    expect(JSON.parse(readFileSync(join(dir, 'spend-caps.json'), 'utf8')).perAgentUsd).toBe(1)
    const row = (fleet.attentionPayload().agents as Array<{ agentId: string; spend: { usd: number; fraction: number } | null }>).find((r) => r.agentId === 'a')
    expect(row?.spend).toMatchObject({ usd: 2.16, fraction: 1.5 })
  })

  it('leaves the spend brake off until a cap is set', () => {
    tokens = 50_000_000
    expect(fleet.spendCheck(session('a')).action).toBe('run')
    expect(errors).toEqual([])
  })

  it('stopAll cancels every active agent but the one kept', async () => {
    const out = await fleet.stopAll('b')
    expect(out.cancelled).toEqual(['a'])
    expect(cancelled).toEqual(['a'])
    expect(fleet.attention.get('a')?.state).toBe('idle')
  })

  it('exposes the local command surface', async () => {
    await expect(fleet.command('nope', {})).rejects.toThrow(/unknown fleet action/)
    const att = await fleet.command('attention', {}) as { agents: unknown[] }
    expect(att.agents).toHaveLength(2)
    const stopped = await fleet.command('stop-all', { except: 'a' }) as { cancelled: string[] }
    expect(stopped.cancelled).toEqual(['b'])
    const status = await fleet.command('gate-status', {}) as { enabled: boolean; rules: number; installed: boolean }
    expect(status).toMatchObject({ enabled: true, installed: false })
    expect(status.rules).toBeGreaterThan(10)
    const caps = await fleet.command('spend-set', { perDayUsd: 42 }) as { caps: { perDayUsd: number; enabled: boolean } }
    expect(caps.caps).toMatchObject({ perDayUsd: 42, enabled: true })
  })
})
