/**
 * Idempotently install the Harness Compute opencode skill into
 * ~/.config/opencode/skills/harness-compute/SKILL.md, so any opencode session — including one
 * running inside a Harness swarm pane — can help the user start or use a local model without
 * ever being told what the underlying CLI it shells out to is called.
 *
 * The skill's own prose is not duplicated here: it lives in `docs/skills/harness-compute.md`,
 * one file for every agent — it tells the agent to add a custom provider to itself, which every
 * coding agent knows how to do, rather than carrying a page per agent's config format. This just adds the frontmatter opencode's skill loader requires.
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

const FRONTMATTER = `---
name: harness-compute
description: Run AI models on the user's own machines under their Harness account and chat with them from this agent. Use when the user asks to start or serve a local model, run a model on this machine, add a custom provider for those models, or check what their machines are currently serving.
license: MIT
compatibility: opencode
metadata:
  source: autonomous-harness (docs/skills/harness-compute.md)
---

`

/** Idempotently drop the assembled Harness Compute skill into ~/.config/opencode/skills/. */
export function installOpencodeHarnessComputeSkill(): void {
  let core: string
  try {
    core = readFileSync(skillSourcePath('harness-compute.md'), 'utf-8')
  } catch (err) {
    // Best-effort, same posture as every other engine install in hooks.ts: a missing or unreadable
    // source must never fail `harness start`, only skip this one skill.
    console.error('[hooks] failed to read Harness Compute skill sources:', err)
    return
  }
  const source = FRONTMATTER + core.trimEnd() + '\n'
  try {
    if (existsSync(SKILL_PATH) && readFileSync(SKILL_PATH, 'utf-8') === source) {
      console.log('[hooks] Harness Compute opencode skill already installed')
      return
    }
  } catch { /* unreadable — rewrite it */ }
  try {
    mkdirSync(dirname(SKILL_PATH), { recursive: true })
    const tmp = `${SKILL_PATH}.${process.pid}.tmp`
    writeFileSync(tmp, source)
    renameSync(tmp, SKILL_PATH)
    console.log(`[hooks] installed Harness Compute opencode skill → ${SKILL_PATH}`)
    console.log('[hooks] (a NEW opencode session picks this up automatically)')
  } catch (err) {
    console.error('[hooks] failed to write Harness Compute opencode skill:', err)
  }
}
