/**
 * `ensureHarnessGrid` against a fake `grid` first on PATH — the same seam `gridCommand.spec.ts`
 * uses, for the same reason: the real binary talks to a control plane, and the questions worth
 * asking here are all about which argv this module sends and what it believes about the answer.
 */
import { afterEach, describe, expect, it } from 'vitest'
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const dirs: string[] = []
afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true })
  delete process.env.HARNESS_GRID_BIN
})

/**
 * A `grid` whose behaviour is data: a JSON script the test writes beside it decides what each verb
 * answers, and every invocation is appended to a log the test reads back.
 */
const FAKE_GRID = `#!/usr/bin/env node
const fs = require('fs')
const log = process.env.FAKE_GRID_LOG
const plan = JSON.parse(fs.readFileSync(process.env.FAKE_GRID_PLAN, 'utf8'))
const args = process.argv.slice(2).filter((a) => a !== '--remote')
const verb = args[0] || ''
const calls = fs.existsSync(log) ? JSON.parse(fs.readFileSync(log, 'utf8')) : []
calls.push(process.argv.slice(2))
fs.writeFileSync(log, JSON.stringify(calls))
const step = plan[verb]
if (!step) { process.exit(0) }
// \`ls\` may answer differently before and after a create, so its answer can be a LIST of turns.
const turn = Array.isArray(step) ? (step[calls.filter((c) => c.includes(verb)).length - 1] ?? step[step.length - 1]) : step
if (turn.stdout) process.stdout.write(turn.stdout)
if (turn.stderr) process.stderr.write(turn.stderr)
process.exit(turn.exit ?? 0)
`

interface Turn { stdout?: string; stderr?: string; exit?: number }

function fakeGrid(plan: Record<string, Turn | Turn[]>): { calls: () => string[][] } {
  const root = mkdtempSync(join(tmpdir(), 'grid-ensure-'))
  dirs.push(root)
  const bin = join(root, 'grid')
  writeFileSync(bin, FAKE_GRID)
  chmodSync(bin, 0o755)
  const planFile = join(root, 'plan.json')
  writeFileSync(planFile, JSON.stringify(plan))
  const log = join(root, 'calls.json')
  process.env.HARNESS_GRID_BIN = bin
  process.env.FAKE_GRID_PLAN = planFile
  process.env.FAKE_GRID_LOG = log
  return {
    calls: () => JSON.parse(readFileSync(log, 'utf8')) as string[][],
  }
}

const VERSION_OK: Turn = { stdout: 'grid 0.3.46\n' }
const rows = (...names: string[]): string =>
  JSON.stringify(names.map((n) => ({ grid: n, type: 'permissioned-public', id: `grid-${n}` })))

async function ensure(name = 'someone-7f3a91c4') {
  const { ensureHarnessGrid } = await import('./gridEnsure.js')
  return ensureHarnessGrid(name)
}

describe('ensureHarnessGrid', () => {
  it('creates the grid when the account has none, as a private permissioned-public one', async () => {
    const fake = fakeGrid({
      version: VERSION_OK,
      sync: {},
      ls: { stdout: rows('something-else') },
      start: {},
    })
    expect(await ensure()).toEqual({ status: 'created', message: '' })
    const start = fake.calls().find((c) => c.includes('start'))
    // The type is the whole safety property: `permissioned-providers` would open the grid to
    // strangers and switch billing on.
    expect(start).toEqual(['--remote', 'start', 'someone-7f3a91c4', '--type', 'permissioned-public'])
  })

  it('syncs AGAIN after creating, so the new grid has its access token', async () => {
    // A just-created grid has no per-grid token locally; `grid info --env` and `grid join` both
    // refuse until a refresh. Measured against the real control plane.
    const fake = fakeGrid({ version: VERSION_OK, sync: {}, ls: { stdout: rows() }, start: {} })
    expect((await ensure()).status).toBe('created')
    const verbs = fake.calls().map((c) => c.find((a) => a !== '--remote'))
    expect(verbs.filter((v) => v === 'sync').length).toBe(2)
    expect(verbs.lastIndexOf('sync')).toBeGreaterThan(verbs.indexOf('start'))
  })

  it('does nothing when the grid is already there', async () => {
    const fake = fakeGrid({ version: VERSION_OK, sync: {}, ls: { stdout: rows('someone-7f3a91c4') } })
    expect(await ensure()).toEqual({ status: 'existed', message: '' })
    expect(fake.calls().some((c) => c.includes('start'))).toBe(false)
  })

  it('syncs BEFORE looking, so a grid another machine made is seen', async () => {
    const fake = fakeGrid({ version: VERSION_OK, sync: {}, ls: { stdout: rows('someone-7f3a91c4') } })
    await ensure()
    const order = fake.calls().map((c) => c.find((a) => a !== '--remote'))
    expect(order.indexOf('sync')).toBeLessThan(order.indexOf('ls'))
  })

  it('adopts rather than duplicating when another machine won the create race', async () => {
    // The control plane rejects a duplicate name, and the refusal is prose — so this is resolved by
    // looking again, not by reading the error.
    const fake = fakeGrid({
      version: VERSION_OK,
      sync: {},
      ls: [{ stdout: rows() }, { stdout: rows('someone-7f3a91c4') }],
      start: { exit: 1, stderr: 'POST …/managed-networks failed (409): name already taken\n' },
    })
    expect(await ensure()).toEqual({ status: 'adopted', message: '' })
    expect(fake.calls().filter((c) => c.includes('sync')).length).toBe(2)
  })

  it('reports grid’s own words when the create really failed', async () => {
    fakeGrid({
      version: VERSION_OK,
      sync: {},
      ls: { stdout: rows() },
      start: { exit: 1, stderr: 'the control plane is unreachable\n' },
    })
    const result = await ensure()
    expect(result.status).toBe('failed')
    expect(result.message).toContain('control plane is unreachable')
  })

  it('skips, without touching the grid, when the binary is older than the floor', async () => {
    const fake = fakeGrid({ version: { stdout: 'grid 0.3.34\n' } })
    const result = await ensure()
    expect(result.status).toBe('skipped')
    expect(result.message).toContain('0.3.36')
    expect(fake.calls().some((c) => c.includes('start'))).toBe(false)
  })

  it('skips when there is no grid at all, and never throws', async () => {
    process.env.HARNESS_GRID_BIN = join(tmpdir(), 'definitely-not-a-grid-binary')
    const result = await ensure()
    expect(result.status).toBe('skipped')
  })

  it('refuses an empty name rather than creating a grid called nothing', async () => {
    fakeGrid({ version: VERSION_OK })
    expect((await ensure('   ')).status).toBe('skipped')
  })
})
