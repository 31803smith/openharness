// Originally written by Fred Nix (@nixfred) in github.com/nixfred/openharness (MIT), as nixfredWiring.spec.ts.

import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { FleetControl, type FleetControlDeps, type FleetSessionLike } from './control.js'

const session = (agentId: string, extra: Partial<FleetSessionLike> = {}): FleetSessionLike => ({
  agentId, sessionId: `s-${agentId}`, engine: 'claude', active: true, tmuxPane: '%3', cwd: '/tmp/proj', name: agentId, model: 'claude-sonnet', ...extra,
})

describe('FleetControl', () => {
  let dir: string
  let sent: Array<{ type: string; payload: Record<string, unknown> }>
  let cancelled: string[]
  let sessions: FleetSessionLike[]
  let fleet: FleetControl
  let now: number

  const deps = (): FleetControlDeps => ({
    dataDir: dir,
    machineId: () => 'm-1',
    machineName: () => 'gus',
    sessions: () => sessions,
    sendLocal: (f) => { sent.push(f) },
    cancelAgent: async (id) => { cancelled.push(id); return true },
    now: () => now,
  })

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'fleet-'))
    sent = []; cancelled = []; now = Date.UTC(2026, 8, 26, 16, 0)
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
  })
})
