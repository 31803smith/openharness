// Explicit opt-in: these checks run the real package installers and native local simulations.
// All index entries and workspaces stay in disposable directories.
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { fileURLToPath } from 'node:url'
import { env } from '../config/env.js'
import { installDsh, removeDsh } from './install.js'
import { installedDsh, invalidateInstalledDsh, listInstalledDsh } from './installed.js'
import { materializeWorkspace } from './materialize.js'
import { DshViewerManager } from './viewer.js'

const store = realpathSync(fileURLToPath(new URL('../../../store/', import.meta.url)))
const packages = ['juce-agent-toolkit', 'foam-agent', 'autoresearch-mlx', 'ableton-ai', 'dimos', 'simskill', 'bonsai-mcp', 'comfy-mcp']

describe.runIf(process.env.HARNESS_STUDIO_INTEGRATION === '1')('specialist studios through the real Harness lifecycle', () => {
  let root: string
  let savedRoot: string
  let manager: DshViewerManager
  const report: { name: string; checks: string[] }[] = []
  beforeAll(async () => {
    root = realpathSync(mkdtempSync(join(tmpdir(), 'harness-studio-lifecycle-')))
    savedRoot = env.DSH_DIR
    env.DSH_DIR = join(root, 'installed')
    invalidateInstalledDsh()
    manager = new DshViewerManager({ onUrl: () => {} })
    const viewer = await installDsh({ source: join(store, 'viewers/studio-viewer'), link: true })
    expect(viewer.ok, JSON.stringify(viewer)).toBe(true)
  }, 120_000)
  afterAll(async () => {
    await manager?.stopAll()
    const output = join(store, 'viewers/studio-viewer/test-results')
    mkdirSync(output, { recursive: true })
    writeFileSync(join(output, 'lifecycle-report.json'), JSON.stringify(report, null, 2))
    env.DSH_DIR = savedRoot
    invalidateInstalledDsh()
    if (root) rmSync(root, { recursive: true, force: true })
  })
  for (const name of packages) it(`${name}: installs, initializes, launches, runs, restores and removes`, async () => {
    const phases: string[] = []
    const result = await installDsh({ source: join(store, 'agents', name), expectedId: `autonomous/${name}`, link: true,
      setupTimeoutMs: 600_000, onProgress: p => phases.push(p.phase) })
    expect(result.ok, JSON.stringify(result)).toBe(true)
    if (!result.ok) return
    expect(phases).toEqual(['clone', 'setup', 'doctor', 'done'])
    expect(installedDsh(result.installed.id)?.realDir).toBe(result.installed.realDir)
    const workspace = join(root, `workspace ${name}`)
    mkdirSync(workspace)
    const materialized = await materializeWorkspace(result.installed, workspace)
    expect(materialized.warnings).toEqual([])
    expect(readFileSync(join(workspace, 'AGENTS.md'), 'utf8')).toContain(`autonomous/${name}`)
    expect(lstatSync(join(workspace, '.agents/skills', name)).isSymbolicLink()).toBe(true)
    const verdict = JSON.parse(readFileSync(join(workspace, '.harness/verdict.json'), 'utf8'))
    expect(verdict.ready).toBe(true)
    expect(existsSync(join(workspace, verdict.artifact))).toBe(true)
    await manager.start(name, result.installed, workspace)
    const url = manager.url(name)
    expect(url).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/$/)
    const first = await (await fetch(`${url}api/state`)).json()
    expect(first.history).toHaveLength(1)
    const run = await fetch(`${url}api/run`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: first.config.actions[0].id, parameters: first.project.parameters, revision: first.revision }) })
    expect(run.status).toBe(202)
    await expect.poll(async () => (await (await fetch(`${url}api/state`)).json()).job.status, { timeout: 120_000, interval: 300 }).toBe('done')
    const current = await (await fetch(`${url}api/state`)).json()
    expect(current.history).toHaveLength(2)
    for (const artifact of current.result.artifacts) expect((await fetch(`${url}artifacts/${artifact.path}`)).status).toBe(200)
    await manager.stop(name)
    expect(manager.url(name)).toBe(null)
    const again = await materializeWorkspace(result.installed, workspace)
    expect(again.created).toEqual([])
    expect(again.initLines).toEqual([])
    await manager.start(name, result.installed, workspace)
    const restored = await (await fetch(`${manager.url(name)}api/state`)).json()
    expect(restored.result.id).toBe(current.result.id)
    expect(restored.history).toHaveLength(2)
    await manager.stop(name)
    expect(removeDsh(result.installed.id)).toEqual({ ok: true })
    expect(installedDsh(result.installed.id)).toBeUndefined()
    expect(existsSync(join(store, 'agents', name, 'harness.json'))).toBe(true)
    expect(listInstalledDsh().map(d => d.id)).toEqual(['autonomous/studio-viewer'])
    report.push({ name, checks: ['install', 'setup', 'doctor', 'index', 'materialize', 'skill discovery', 'verdict',
      'viewer launch', 'run', 'artifact downloads', 'stop', 'idempotent materialization', 'restore', 'remove'] })
  }, 900_000)
})
