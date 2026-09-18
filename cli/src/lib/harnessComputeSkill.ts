/**
 * Idempotently install the Harness Compute opencode skill into
 * ~/.config/opencode/skills/harness-compute/SKILL.md, so any opencode session — including one
 * running inside a Harness swarm pane — can help the user start or use a local model without
 * ever being told what the underlying CLI it shells out to is called.
 *
 * The skill's own prose is not duplicated here: it lives in `docs/skills/harness-compute.md`,
 * one file for every agent — it starts the model and then points the user at the app's model
 * picker, which is what actually switches an agent (agent_retarget); the skill never touches an
 * agent's own config. This just adds the frontmatter opencode's skill loader requires.
 *
 * Beside the skill goes the `harness-compute` AGENT definition (`docs/skills/harness-compute.agent.md` →
 * ~/.config/opencode/agents/harness-compute.md): the thing `opencode --agent harness-compute` opens a pane
 * AS, whose whole job is to load that skill and follow it. The source file already carries the exact
 * frontmatter opencode reads (`name`, `mode: primary`, `permission: question: allow`), so it is
 * installed verbatim.
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync, renameSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import { env } from '../config/env.js'

const cliDir = dirname(fileURLToPath(import.meta.url))

/**
 * The docs as the build embedded them — a JSON object of file name → text, injected by esbuild
 * `define` in build-bundle.mjs and build.mjs the way `__DSH_REGISTRY__` is (dsh/registry.ts).
 *
 * INSIDE cli.js rather than shipped as files beside it, because nothing ships files beside cli.js:
 * upload-cli.sh publishes `cli.js` and `notify.mjs` and nothing else, install.sh fetches those two,
 * the self-updater swaps those two. The `dist/skills/` the bundle used to lay down reached no
 * machine — a daemon installed from the CDN logged "failed to read Harness Compute skill sources"
 * and installed nothing, silently, while a working tree that happened to have a `skills/` beside its
 * cli.js looked fine. Embedded, the docs travel wherever cli.js does and can never be a version
 * behind the code that installs them.
 */
declare const __HARNESS_SKILLS__: string | undefined

function embeddedSkill(name: string): string | null {
  if (typeof __HARNESS_SKILLS__ === 'undefined') return null
  const skills = JSON.parse(__HARNESS_SKILLS__) as Record<string, unknown>
  const text = skills[name]
  return typeof text === 'string' ? text : null
}

/** Dev, per-file (tsx, vitest): this file runs from <appRoot>/cli/src/lib/, and the docs are three
 *  levels up, at <appRoot>/docs/skills/. Nothing is embedded there, and nothing needs to be. */
function devSkillPath(name: string): string {
  return join(cliDir, '..', '..', '..', 'docs', 'skills', name)
}

const SKILL_PATH = join(env.OPENCODE_SKILL_DIR, 'harness-compute', 'SKILL.md')
const AGENT_PATH = join(env.OPENCODE_AGENT_DIR, 'harness-compute.md')

const FRONTMATTER = `---
name: harness-compute
description: Run AI models on the user's own machines under their Harness account, so any agent can switch to them from its model picker. Use when the user asks to start or serve a local model, run a model on this machine, stop one, or check what their machines are currently serving.
license: MIT
compatibility: opencode
metadata:
  source: autonomous-harness (docs/skills/harness-compute.md)
---

`

/**
 * Write `source` to `target` unless it is already there byte-for-byte. Atomic (temp + rename), so a
 * session that reads the file mid-install sees the old one or the new one, never half of either.
 * Best-effort: a failure is logged and skipped, never thrown — nothing here may fail `harness start`.
 */
function installFile(label: string, target: string, source: string): void {
  try {
    if (existsSync(target) && readFileSync(target, 'utf-8') === source) {
      console.log(`[hooks] ${label} already installed`)
      return
    }
  } catch { /* unreadable — rewrite it */ }
  try {
    mkdirSync(dirname(target), { recursive: true })
    const tmp = `${target}.${process.pid}.tmp`
    writeFileSync(tmp, source)
    renameSync(tmp, target)
    console.log(`[hooks] installed ${label} → ${target}`)
    console.log('[hooks] (a NEW opencode session picks this up automatically)')
  } catch (err) {
    console.error(`[hooks] failed to write ${label}:`, err)
  }
}

/** The doc `name`: what the build embedded, else the file under docs/skills/ (dev), else null (logged). */
function readSkillSource(label: string, name: string): string | null {
  const embedded = embeddedSkill(name)
  if (embedded !== null) return embedded
  try {
    return readFileSync(devSkillPath(name), 'utf-8')
  } catch (err) {
    // Best-effort, same posture as every other engine install in hooks.ts: a missing or unreadable
    // source must never fail `harness start`, only skip this one file.
    console.error(`[hooks] failed to read ${label} sources:`, err)
    return null
  }
}

/** Idempotently drop the assembled Harness Compute skill into ~/.config/opencode/skills/, and the
 *  `harness-compute` agent that follows it into ~/.config/opencode/agents/. */
export function installOpencodeHarnessComputeSkill(): void {
  const core = readSkillSource('Harness Compute skill', 'harness-compute.md')
  if (core !== null) installFile('Harness Compute opencode skill', SKILL_PATH, FRONTMATTER + core.trimEnd() + '\n')
  // Verbatim: the source file IS the agent definition, frontmatter included.
  const agent = readSkillSource('harness-compute agent', 'harness-compute.agent.md')
  if (agent !== null) installFile('harness-compute opencode agent', AGENT_PATH, agent)
}
