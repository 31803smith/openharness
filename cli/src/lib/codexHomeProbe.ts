/**
 * Which Codex profile a live `codex` process was launched under, read off its environment.
 *
 * The registry's `codexHome` is chosen at `agent_create` and carried forward — but a codex pane the
 * daemon did not create (started by hand, or a row discovery had to mint again) has nothing to carry.
 * Its transcript lives under `<CODEX_HOME>/sessions`, so without this the hook's transcript path fails
 * `validTranscriptPath` against the default profile and session repair scans the wrong root. Same
 * cached env read `probeGridAssignment` uses: one `ps` per process for its whole life.
 *
 * Three answers, same contract as the grid probe: a path when the process runs under a non-default
 * profile, `null` when it runs under the machine's default (or CODEX_HOME is unset), and `undefined`
 * when the process could not be read — which must never overwrite what the registry already knows.
 */

import { realpathSync } from 'node:fs'
import { isAbsolute } from 'node:path'
import { env } from '../config/env.js'
import type { AgentEngine } from '../engines/types.js'
import { readProcessEnv } from './processEnv.js'
import type { ProcessIdentity } from './registry.js'

function canonical(path: string): string {
  try { return realpathSync(path) } catch { return path }
}

/** Pure half, for specs and for callers that already hold the environment. */
export function codexHomeFromEnv(engine: AgentEngine, processEnv: Record<string, string>, defaultHome = env.CODEX_HOME): string | null {
  if (engine !== 'codex') return null
  const home = processEnv.CODEX_HOME
  if (!home || !isAbsolute(home) || home.length > 4096 || /[\x00-\x1f\x7f]/.test(home)) return null
  return canonical(home) === canonical(defaultHome) ? null : home
}

export async function probeCodexHome(identity: ProcessIdentity, engine: AgentEngine): Promise<string | null | undefined> {
  if (engine !== 'codex') return null
  const processEnv = await readProcessEnv(identity)
  if (!processEnv) return undefined
  return codexHomeFromEnv(engine, processEnv)
}
