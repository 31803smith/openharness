import { describe, expect, it, vi } from 'vitest'
import { buildLaunchOverrides, validateLaunchOverrides, type LaunchOverridesDeps } from './launchOverrides.js'
import { GRID_CONFLICTING_ENV_VARS, type GridLaunchOverride } from './gridLaunch.js'

const GRID: GridLaunchOverride = {
  networkId: 'grid-abc',
  networkName: 'Team grid',
  baseUrl: 'https://grid.example/grid-abc/relay/v1',
  apiKey: 'gridkey-abc123',
  model: 'gpt-5',
}

function deps(overrides: Partial<LaunchOverridesDeps> = {}) {
  const calls: string[] = []
  const d: LaunchOverridesDeps = {
    configDirFor: (_engine, launch) => launch.configDir,
    writeGridConfigDir: async (key) => { calls.push(`writeConfig:${key}`); return `/state/grid-engine-config/${key}` },
    tmuxSupportsSessionEnv: async () => true,
    installCodexHooks: (home) => { calls.push(`hooks:${home}`) },
    ...overrides,
  }
  return { d, calls }
}

describe('buildLaunchOverrides — a relaunch comes back where the agent was', () => {
  it('rebuilds a grid launch from the persisted override: env with the key, argv, and the vendor variables to clear', async () => {
    const { d, calls } = deps()
    const result = await buildLaunchOverrides(d, 'claude', { gridLaunch: GRID }, 'agent-1')
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.overrides.env).toMatchObject({ ANTHROPIC_AUTH_TOKEN: 'gridkey-abc123', ANTHROPIC_MODEL: 'gpt-5' })
    expect(result.overrides.env.ANTHROPIC_BASE_URL).toMatch(/^https:\/\/grid\.example\/grid-abc\/relay/)
    expect(result.overrides.extraArgs).toEqual(expect.arrayContaining(['--disallowedTools=WebSearch,WebFetch']))
    // Everything the launch does not set itself, so an inherited key cannot outrank the grid.
    for (const name of GRID_CONFLICTING_ENV_VARS) {
      expect(result.overrides.clearEnv.includes(name)).toBe(!(name in result.overrides.env))
    }
    expect(calls).toEqual([])
  })

  it('writes a file-configured engine its config directory keyed on the agent, and points the env at it', async () => {
    const { d, calls } = deps()
    const result = await buildLaunchOverrides(d, 'pi', { gridLaunch: GRID }, 'agent-1')
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(calls).toEqual(['writeConfig:agent-1'])
    expect(result.overrides.env.PI_CODING_AGENT_DIR).toBe('/state/grid-engine-config/agent-1')
    expect(result.overrides.clearEnv).not.toContain('PI_CODING_AGENT_DIR')
  })

  it('refuses rather than falling back when the grid cannot be honoured', async () => {
    expect(await buildLaunchOverrides(deps().d, 'cursor', { gridLaunch: GRID }, 'a')).toMatchObject({ ok: false, error: 'GRID_ENGINE_UNSUPPORTED' })
    expect(await buildLaunchOverrides(deps({ tmuxSupportsSessionEnv: async () => false }).d, 'claude', { gridLaunch: GRID }, 'a'))
      .toMatchObject({ ok: false, error: 'TMUX_TOO_OLD_FOR_GRID', detail: expect.stringContaining('Team grid') })
    expect(await buildLaunchOverrides(deps({ writeGridConfigDir: async () => { throw new Error('disk full') } }).d, 'pi', { gridLaunch: GRID }, 'a'))
      .toMatchObject({ ok: false, error: 'GRID_CONFIG_FAILED', detail: expect.stringContaining('disk full') })
  })

  it('validation refuses the same launches without writing anything', async () => {
    const { d, calls } = deps({ tmuxSupportsSessionEnv: async () => false })
    expect(await validateLaunchOverrides(d, 'claude', { gridLaunch: GRID })).toMatchObject({ ok: false, error: 'TMUX_TOO_OLD_FOR_GRID' })
    expect(await validateLaunchOverrides(d, 'cursor', { gridLaunch: GRID })).toMatchObject({ ok: false, error: 'GRID_ENGINE_UNSUPPORTED' })
    expect(await validateLaunchOverrides(d, 'pi', { gridLaunch: null, codexHome: '/x' })).toEqual({ ok: true })
    expect(await validateLaunchOverrides(deps().d, 'pi', { gridLaunch: GRID })).toEqual({ ok: true })
    expect(calls).toEqual([])
  })

  it('a Codex profile gets its CODEX_HOME and its hooks, and clears nothing', async () => {
    const { d, calls } = deps()
    const result = await buildLaunchOverrides(d, 'codex', { gridLaunch: null, codexHome: '/home/u/.codex-work' }, 'agent-2')
    expect(result).toEqual({ ok: true, overrides: { env: { CODEX_HOME: '/home/u/.codex-work' }, extraArgs: [], clearEnv: [] } })
    expect(calls).toEqual(['hooks:/home/u/.codex-work'])
  })

  it('an agent on its own login gets nothing — its own variables are the point', async () => {
    const { d, calls } = deps()
    expect(await buildLaunchOverrides(d, 'claude', {}, 'a')).toEqual({ ok: true, overrides: { env: {}, extraArgs: [], clearEnv: [] } })
    expect(await buildLaunchOverrides(d, 'claude', { gridLaunch: null, codexHome: null }, 'a')).toMatchObject({ ok: true })
    expect(calls).toEqual([])
  })

  it('never lets the key into argv', async () => {
    for (const engine of ['claude', 'codex', 'opencode', 'hermes', 'grok', 'pi', 'copilot'] as const) {
      const result = await buildLaunchOverrides(deps().d, engine, { gridLaunch: { ...GRID, model: 'm' } }, 'a')
      expect(result.ok).toBe(true)
      if (result.ok) expect(result.overrides.extraArgs.join(' ')).not.toContain('gridkey-abc123')
    }
  })
})

describe('buildLaunchOverrides — coming back off a grid', () => {
  it('re-selects the model the agent was on before it left', async () => {
    // Without this the engine restores the model its OWN session file remembers — the grid's — fails
    // to resolve it, and falls back to a house default. Measured on Claude Code: "Session model
    // Qwen3.6-35B-A3B-UD-Q5_K_XL could not be restored … using opus instead."
    const result = await buildLaunchOverrides(deps().d, 'claude', { subscriptionModel: 'opus' }, 'a')
    expect(result).toMatchObject({ ok: true, overrides: { env: { ANTHROPIC_MODEL: 'opus' } } })
  })

  it('uses argv for an engine whose interactive CLI resolves the model there', async () => {
    const result = await buildLaunchOverrides(deps().d, 'codex', { subscriptionModel: 'gpt-5-codex' }, 'a')
    expect(result).toMatchObject({ ok: true, overrides: { extraArgs: ['-m', 'gpt-5-codex'] } })
  })

  it('adds nothing when there is no model to come back to', async () => {
    const result = await buildLaunchOverrides(deps().d, 'claude', {}, 'a')
    expect(result).toMatchObject({ ok: true, overrides: { env: {}, extraArgs: [] } })
  })

  it('never lets a remembered model reach a GRID launch — that launch names its own', async () => {
    const result = await buildLaunchOverrides(
      deps().d, 'claude', { gridLaunch: GRID, subscriptionModel: 'opus' }, 'a',
    )
    expect(result.ok).toBe(true)
    if (!result.ok) return
    // The grid's model, not the remembered one.
    expect(result.overrides.env.ANTHROPIC_MODEL).toBe('gpt-5')
  })
})
