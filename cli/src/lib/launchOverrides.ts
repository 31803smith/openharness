/**
 * What a pane has to be launched WITH, beyond the engine's own argv, for the engine to come back
 * where it was: on the same grid with the same credential, or under the same Codex profile.
 *
 * `agent_create` assembles this from the desktop's fresh `GridLaunchOverride`. Every later relaunch of
 * the same agent — a restart in place, a pane recreated after a reboot — has to assemble the SAME
 * thing from what the registry kept (`gridLaunch`, `codexHome`), or the engine silently comes back on
 * its own login, spending the wrong account while looking identical. Written once so the three
 * callers cannot drift: the half that drifts is the half nobody ran today.
 *
 * Dependency-injected like restoreAgents.ts, because the two machine-specific parts (the tmux version
 * probe and the config directory writer) are exactly the parts worth stubbing in a spec.
 */

import { join } from 'node:path'
import type { AgentEngine } from '../engines/types.js'
import {
  buildGridEngineLaunch,
  gridConflictingEnvToClear,
  type GridEngineLaunch,
  type GridLaunchOverride,
} from './gridLaunch.js'
import { TMUX_SESSION_ENV_MIN } from './tmuxVersion.js'
import type { DshLaunch } from '../dsh/launch.js'

export interface LaunchOverrides {
  /** Layered over the pane's inherited environment. The grid key lives here, and only here. */
  env: Record<string, string>
  /** Appended to the engine's argv (`-c model_providers…`, `-m …`, `--mcp-config …`). */
  extraArgs: string[]
  /** Vendor credentials the launch must hide from the engine — see `gridConflictingEnvToClear`. */
  clearEnv: string[]
}

export type LaunchOverridesResult =
  | { ok: true; overrides: LaunchOverrides }
  | { ok: false; error: string; detail: string }

export interface LaunchOverridesDeps {
  /** The config directory this MACHINE can give the launch, or none — cli.ts prunes Hermes's. */
  configDirFor: (engine: AgentEngine, launch: GridEngineLaunch) => GridEngineLaunch['configDir']
  writeGridConfigDir: (
    key: string,
    files: NonNullable<GridEngineLaunch['configDir']>['files'],
    links: NonNullable<GridEngineLaunch['configDir']>['links'],
  ) => Promise<string>
  tmuxSupportsSessionEnv: () => Promise<boolean>
  /** Install the daemon's hooks into a non-default Codex profile. The caller decides whether hook
   *  installation is enabled at all. */
  installCodexHooks: (codexHome: string) => void
  /** What a DSH adds to the launch (its env and argv), or null when it is not installed here any
   *  more — in which case the agent relaunches as its plain base engine and says so in the log. */
  dshLaunch?: (dsh: string, workspace: string) => DshLaunch | null
}

/** Where the agent should come back: the registry row, or an override the desktop just sent. */
export interface LaunchSource {
  gridLaunch?: GridLaunchOverride | null
  codexHome?: string | null
  /** The DSH the agent was created as; its env rides on every relaunch (`HARNESS_DSH` included). */
  dsh?: string | null
  /** The workspace, for the DSH's `${workspace}` — the registry row's `cwd`. */
  cwd?: string | null
}

/** Fresh each time: callers hand `env` to tmux and may extend it, and a shared object would carry
 *  one relaunch's additions into the next. */
const noOverrides = (): LaunchOverrides => ({ env: {}, extraArgs: [], clearEnv: [] })

/**
 * Build the overrides for relaunching `engine` from `source`. `configKey` names the config directory
 * a file-configured engine gets (`writeGridConfigDir`); key it on the agent so relaunching the same
 * agent rewrites one directory rather than leaving a trail of them.
 *
 * A grid the launch cannot honour is a refusal, never a fallback — the rule `agent_create` sets.
 */
/**
 * The refusals that need nothing written: the engine has no way onto a grid, or this tmux cannot
 * give a pane its own environment. Split out so a caller with a live process to protect can refuse
 * BEFORE it decides to touch anything (retarget checks these ahead of its busy guards, and only
 * builds — config directory included — once it holds the pane).
 */
export async function validateLaunchOverrides(
  deps: Pick<LaunchOverridesDeps, 'tmuxSupportsSessionEnv'>,
  engine: AgentEngine,
  source: LaunchSource,
): Promise<{ ok: true } | { ok: false; error: string; detail: string }> {
  if (!source.gridLaunch) return { ok: true }
  const built = buildGridEngineLaunch(engine, source.gridLaunch)
  if (!built.ok) return { ok: false, error: built.error, detail: built.detail }
  // Only a launch that SETS variables needs the tmux that can set them.
  if (!(await deps.tmuxSupportsSessionEnv())) {
    return {
      ok: false,
      error: 'TMUX_TOO_OLD_FOR_GRID',
      detail: `this machine's tmux is older than ${TMUX_SESSION_ENV_MIN.major}.${TMUX_SESSION_ENV_MIN.minor}, `
        + `which is the first version that can give a pane its own environment — so ${engine} could not be `
        + `pointed at grid ${source.gridLaunch.networkName}.`,
    }
  }
  return { ok: true }
}

export async function buildLaunchOverrides(
  deps: LaunchOverridesDeps,
  engine: AgentEngine,
  source: LaunchSource,
  configKey: string,
): Promise<LaunchOverridesResult> {
  const base = await buildBaseLaunchOverrides(deps, engine, source, configKey)
  if (!base.ok || !source.dsh || !source.cwd) return base
  const dsh = deps.dshLaunch?.(source.dsh, source.cwd) ?? null
  if (!dsh) return base
  // The DSH's variables layer over the grid's or the profile's; `HARNESS_*` are the daemon's own and
  // a manifest cannot set them (see `dshLaunch`), so nothing here can shadow a grid credential.
  return {
    ok: true,
    overrides: {
      env: { ...base.overrides.env, ...dsh.env },
      extraArgs: [...base.overrides.extraArgs, ...dsh.args],
      clearEnv: base.overrides.clearEnv,
    },
  }
}

async function buildBaseLaunchOverrides(
  deps: LaunchOverridesDeps,
  engine: AgentEngine,
  source: LaunchSource,
  configKey: string,
): Promise<LaunchOverridesResult> {
  const valid = await validateLaunchOverrides(deps, engine, source)
  if (!valid.ok) return valid
  if (source.gridLaunch) {
    const built = buildGridEngineLaunch(engine, source.gridLaunch)
    if (!built.ok) return { ok: false, error: built.error, detail: built.detail }
    const env: Record<string, string> = { ...built.launch.env }
    const configDir = deps.configDirFor(engine, built.launch)
    if (configDir) {
      const { envVar, files, pointAt, links } = configDir
      try {
        const dir = await deps.writeGridConfigDir(configKey, files, links ?? [])
        // Pi is handed the directory; OpenCode's OPENCODE_CONFIG wants the file inside it.
        env[envVar] = pointAt ? join(dir, pointAt) : dir
      } catch (error) {
        const detail = `could not write ${engine}'s grid configuration · ${error instanceof Error ? error.message : error}`
        return { ok: false, error: 'GRID_CONFIG_FAILED', detail }
      }
    }
    // Derived from what this launch actually provides (the config-dir variable included), so an
    // inherited vendor key never outranks the grid the engine was handed.
    return { ok: true, overrides: { env, extraArgs: [...built.launch.args], clearEnv: gridConflictingEnvToClear({ env, args: [] }) } }
  }
  if (source.codexHome) {
    // A Codex agent on a profile OTHER than this machine's default reads hooks.json from THAT folder,
    // not the one `harness login` installed into — without this it fires no hook at all. Idempotent.
    deps.installCodexHooks(source.codexHome)
    return { ok: true, overrides: { env: { CODEX_HOME: source.codexHome }, extraArgs: [], clearEnv: [] } }
  }
  return { ok: true, overrides: noOverrides() }
}
