import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { DshVerdictWatcher, parseVerdict, type DshVerdict } from './verdict.js'

describe('parseVerdict', () => {
  it('reduces a spec-1 verdict to the wire shape', () => {
    const verdict = parseVerdict(JSON.stringify({
      spec: 1,
      ready: false,
      summary: '  2 errors, 1 warning ',
      findings: [
        { severity: 'error', kind: 'a', message: 'x' },
        { severity: 'error', kind: 'b', message: 'y', ref: 'U3.pin7' },
        { severity: 'warning', message: 'z' },
        { severity: 'info', message: 'fyi' },
        null,
      ],
      artifact: 'boards/main.board.json',
      updatedAt: '2026-09-14T20:00:00Z',
      extra: 'ignored',
    }))
    expect(verdict).toEqual<DshVerdict>({
      ready: false,
      summary: '2 errors, 1 warning',
      errors: 2,
      warnings: 1,
      artifact: 'boards/main.board.json',
      phases: [],
      updatedAt: '2026-09-14T20:00:00Z',
    })
  })

  it('keeps the phases in order, sanitised, and never more than twelve', () => {
    const verdict = parseVerdict(JSON.stringify({
      spec: 1,
      ready: false,
      phases: [
        { id: 'build', name: 'Build', state: 'done', artifact: 'model.step' },
        { name: 'Checks', state: 'active' },
        { name: ' Fab ', state: 'someday' },
        { name: '', state: 'done' },
        'nope',
        { id: 'x', state: 'done' },
        { name: 'Bad path', state: 'done', artifact: '../out.step' },
      ],
    }))
    expect(verdict?.phases).toEqual([
      { id: 'build', name: 'Build', state: 'done', artifact: 'model.step' },
      { id: 'checks', name: 'Checks', state: 'active', artifact: null },
      { id: 'fab', name: 'Fab', state: 'pending', artifact: null },
      { id: 'bad-path', name: 'Bad path', state: 'done', artifact: null },
    ])
    const many = parseVerdict(JSON.stringify({
      spec: 1, ready: true, phases: Array.from({ length: 20 }, (_, i) => ({ name: `P${i}` })),
    }))
    expect(many?.phases).toHaveLength(12)
    expect(parseVerdict(JSON.stringify({ spec: 1, ready: true, phases: 'later' }))?.phases).toEqual([])
  })

  it('refuses what is not a verdict, and scrubs an artifact that leaves the workspace', () => {
    expect(parseVerdict('nope')).toBeNull()
    expect(parseVerdict('[]')).toBeNull()
    expect(parseVerdict(JSON.stringify({ spec: 2, ready: true }))).toBeNull()
    expect(parseVerdict(JSON.stringify({ spec: 1, ready: 'yes' }))).toBeNull()
    expect(parseVerdict(JSON.stringify({ spec: 1, ready: true, artifact: '../x.step' }))?.artifact).toBeNull()
    expect(parseVerdict(JSON.stringify({ spec: 1, ready: true, artifact: '/abs.step' }))?.artifact).toBeNull()
    expect(parseVerdict(JSON.stringify({ spec: 1, ready: true, updatedAt: 'yesterday' }))?.updatedAt).toBeNull()
  })
})

describe('DshVerdictWatcher', () => {
  let workspace: string
  let watcher: DshVerdictWatcher | null = null
  beforeEach(() => { workspace = mkdtempSync(join(tmpdir(), 'dsh-verdict-')) })
  afterEach(async () => {
    await watcher?.stop()
    watcher = null
    rmSync(workspace, { recursive: true, force: true })
  })

  it('publishes the existing verdict at watch time and each change after it', async () => {
    const file = join(workspace, '.harness', 'verdict.json')
    mkdirSync(join(workspace, '.harness'), { recursive: true })
    writeFileSync(file, JSON.stringify({ spec: 1, ready: false, summary: 'first' }))
    const seen: Array<DshVerdict | null> = []
    let resolveNext: (() => void) | null = null
    watcher = new DshVerdictWatcher({ onChange: (_agentId, verdict) => { seen.push(verdict); resolveNext?.() } })
    watcher.watch('agent-1', file)
    expect(seen).toHaveLength(1)
    expect(seen[0]?.summary).toBe('first')
    expect(watcher.current('agent-1')?.summary).toBe('first')

    const next = new Promise<void>((resolve) => { resolveNext = resolve })
    // Give chokidar a moment to be ready before the write it must notice.
    await new Promise((resolve) => setTimeout(resolve, 300))
    writeFileSync(file, JSON.stringify({ spec: 1, ready: true, summary: 'second' }))
    await Promise.race([next, new Promise((resolve) => setTimeout(resolve, 4_000))])
    expect(seen.at(-1)?.summary).toBe('second')
    expect(seen.at(-1)?.ready).toBe(true)
  }, 10_000)

  it('creates the directory it watches, so a first verdict lands in a watched place', () => {
    const file = join(workspace, 'nested', '.harness', 'verdict.json')
    watcher = new DshVerdictWatcher({ onChange: () => undefined })
    watcher.watch('agent-2', file)
    const { existsSync } = require('node:fs') as typeof import('node:fs')
    expect(existsSync(join(workspace, 'nested', '.harness'))).toBe(true)
    expect(watcher.current('agent-2')).toBeNull()
    watcher.unwatch('agent-2')
  })
})
