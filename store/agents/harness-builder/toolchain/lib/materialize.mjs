// Lay out a workspace for a harness exactly as the Harness daemon does (store/spec/README.md,
// "Materialization"; cli/src/dsh/materialize.ts), so a proof exercises the harness the way a person's
// New Harness would: template, init, AGENTS.md (and CLAUDE.md on Claude Code), skills linked for the
// engine, .harness/. Kept in step with the daemon by hand; the spec is the contract both follow.
import { spawnSync } from 'node:child_process'
import { cpSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, readlinkSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, join, resolve } from 'node:path'

export const ENGINES = ['claude', 'codex', 'cursor', 'opencode', 'pi', 'hermes', 'commandcode', 'devin', 'muse', 'amp', 'kilo', 'grok', 'agy', 'copilot']

export function readManifest(pkg) {
  return JSON.parse(readFileSync(join(pkg, 'harness.json'), 'utf8'))
}

export function skillsDirFor(engine) {
  return engine === 'claude' ? '.claude/skills' : '.agents/skills'
}

export function expand(value, vars) {
  return String(value).replace(/\$\{(dsh|workspace|home)\}/g, (_, name) => (
    name === 'dsh' ? vars.dsh : name === 'workspace' ? vars.workspace : (vars.home ?? homedir())
  ))
}

/** The environment Harness launches the agent (and runs init) with. */
export function launchEnv(manifest, pkg, workspace) {
  const env = { HARNESS_DSH: manifest.id, HARNESS_DSH_DIR: pkg, HARNESS_WORKSPACE: workspace }
  for (const [key, value] of Object.entries(manifest.agent?.env ?? {})) env[key] = expand(value, { dsh: pkg, workspace })
  return env
}

export function skillDirsIn(dir) {
  if (existsSync(join(dir, 'SKILL.md'))) return [dir]
  let names = []
  try { names = readdirSync(dir) } catch { return [] }
  return names.map((n) => join(dir, n)).filter((p) => {
    try { return statSync(p).isDirectory() && existsSync(join(p, 'SKILL.md')) } catch { return false }
  }).sort()
}

/** Materialize `pkg` into `workspace` for `engine` (default: the manifest's). Returns what it did. */
export function materialize(pkg, workspace, { engine, env: extraEnv = {} } = {}) {
  pkg = resolve(pkg)
  workspace = resolve(workspace)
  const manifest = readManifest(pkg)
  const base = engine ?? manifest.engine ?? 'claude'
  const result = { created: [], kept: [], warnings: [], init: null }
  mkdirSync(workspace, { recursive: true })

  const ws = manifest.workspace ?? {}
  const fresh = ws.marker ? !existsSync(join(workspace, ws.marker)) : true
  if (fresh && ws.template) {
    const template = join(pkg, ws.template)
    if (existsSync(template)) {
      cpSync(template, workspace, { recursive: true, force: false, errorOnExist: false })
      result.created.push('template')
    } else {
      result.warnings.push(`template ${ws.template} is missing`)
    }
  }
  if (fresh && ws.init) {
    const inside = join(pkg, ws.init)
    const command = existsSync(inside) && !/[\s;&|<>$`'"\\]/.test(ws.init) ? `'${inside.replace(/'/g, `'\\''`)}'` : ws.init
    const run = spawnSync('/bin/bash', ['-c', command], {
      cwd: workspace,
      env: { ...process.env, ...extraEnv, ...launchEnv(manifest, pkg, workspace) },
      encoding: 'utf8',
      timeout: 5 * 60_000,
    })
    result.init = { exit: run.status, output: `${run.stdout ?? ''}${run.stderr ?? ''}`.slice(-4000) }
    if (run.status !== 0) result.warnings.push(`init exited ${run.status ?? run.signal}`)
  }

  const instructions = manifest.agent?.instructions
  if (instructions) {
    const source = join(pkg, instructions)
    if (existsSync(source)) {
      const marker = `<!-- harness:dsh ${manifest.id} -->`
      const target = join(workspace, 'AGENTS.md')
      const body = `${marker}\n${readFileSync(source, 'utf8').trim()}\n`
      if (!existsSync(target)) { writeFileSync(target, body); result.created.push('AGENTS.md') }
      else if (!readFileSync(target, 'utf8').includes(marker)) {
        writeFileSync(target, `${readFileSync(target, 'utf8').replace(/\s*$/, '')}\n\n${body}`)
        result.created.push('AGENTS.md (appended)')
      } else result.kept.push('AGENTS.md')
      if (base === 'claude') {
        const claude = join(workspace, 'CLAUDE.md')
        if (!existsSync(claude)) { writeFileSync(claude, '@AGENTS.md\n'); result.created.push('CLAUDE.md') }
        else if (!readFileSync(claude, 'utf8').split('\n').some((l) => l.trim() === '@AGENTS.md')) {
          writeFileSync(claude, `${readFileSync(claude, 'utf8').replace(/\s*$/, '')}\n\n@AGENTS.md\n`)
        }
      }
    } else {
      result.warnings.push(`instructions ${instructions} are missing`)
    }
  }

  const skillsDir = join(workspace, skillsDirFor(base))
  for (const root of manifest.agent?.skills ?? []) {
    const dirs = skillDirsIn(join(pkg, root))
    if (!dirs.length) result.warnings.push(`no SKILL.md under ${root}`)
    mkdirSync(skillsDir, { recursive: true })
    for (const dir of dirs) {
      const link = join(skillsDir, basename(dir))
      let existing = null
      try { existing = lstatSync(link) } catch { existing = null }
      if (existing?.isSymbolicLink()) {
        if (readlinkSync(link) === dir) { result.kept.push(link); continue }
        rmSync(link)
      } else if (existing) { result.warnings.push(`${link} exists and is not a link`); continue }
      symlinkSync(dir, link)
      result.created.push(`${skillsDirFor(base)}/${basename(dir)}`)
    }
  }
  mkdirSync(join(workspace, '.harness'), { recursive: true })
  return result
}
