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

// Same dual-path pattern hooks.ts uses for notify.mjs (import.meta.url is the REAL executing
// file at runtime):
//  - packaged/bundled: cli.js at ~/.harness/cli/cli.js → the docs ship as a SIBLING `skills/` dir
//    (build-bundle.mjs copies them there, same as it copies notify.mjs).
//  - dev/per-file: hooks live at <appRoot>/cli/src/lib/ → the docs are three levels up, at
//    <appRoot>/docs/skills/.
function skillSourcePath(name: string): string {
  const packaged = join(cliDir, 'skills', name)
  const dev = join(cliDir, '..', '..', '..', 'docs', 'skills', name)
  return [packaged, dev].find(existsSync) ?? dev
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

/** The doc at `name` under docs/skills/, or null (logged) when it cannot be read. */
function readSkillSource(label: string, name: string): string | null {
  try {
    return readFileSync(skillSourcePath(name), 'utf-8')
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
