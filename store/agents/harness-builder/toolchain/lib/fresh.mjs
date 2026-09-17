// `builder fresh`: the harness's setup, doctor and init on a simulated new machine.
//
// A copy of the package (without anything setup would produce) in a temporary directory, run under
// `env -i` with a new HOME and Apple's PATH (/usr/bin:/bin:/usr/sbin:/sbin): no Homebrew, no Node, no
// pyenv, nothing from this shell. The HOME holds only what a machine with Harness installed has:
// Harness's own Node (`~/.harness/runtime/current-node`), which runtimes.sh falls back to. Download
// caches (uv, npm) are shared with the Builder's so a second run does not refetch the world; they are
// caches, not machine state a venv depends on.
import { spawnSync } from 'node:child_process'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'
import { readManifest } from './materialize.mjs'

const PRODUCED = new Set(['node_modules', '.venv', '.conda', '.playwright', 'upstream', 'reference', '.git', 'dist', '__pycache__', '.harness'])

export function copyPackage(pkg, dest) {
  mkdirSync(dest, { recursive: true })
  for (const entry of readdirSync(pkg, { withFileTypes: true })) {
    if (PRODUCED.has(entry.name)) continue
    cpSync(join(pkg, entry.name), join(dest, entry.name), {
      recursive: true,
      filter: (src) => !src.split('/').some((part) => PRODUCED.has(part)),
      verbatimSymlinks: true,
    })
  }
}

function tail(text, n = 40) {
  return String(text ?? '').split('\n').slice(-n).join('\n')
}

export function runFresh(pkg, { cacheDir, keep = false, setupTimeoutMs = 45 * 60_000 } = {}) {
  const manifest = readManifest(pkg)
  const root = mkdtempSync(join(tmpdir(), 'harness-builder-fresh-'))
  const home = join(root, 'home')
  const install = join(root, 'install')
  const workspace = join(root, 'workspace')
  mkdirSync(join(home, '.harness', 'runtime'), { recursive: true })
  const currentNode = join(homedir(), '.harness', 'runtime', 'current-node')
  if (existsSync(currentNode)) cpSync(currentNode, join(home, '.harness', 'runtime', 'current-node'))
  copyPackage(pkg, install)
  mkdirSync(workspace, { recursive: true })
  cacheDir ??= join(homedir(), '.cache', 'harness-builder')
  mkdirSync(cacheDir, { recursive: true })

  const env = {
    HOME: home,
    USER: process.env.USER ?? 'builder',
    LANG: 'en_US.UTF-8',
    TMPDIR: tmpdir(),
    PATH: '/usr/bin:/bin:/usr/sbin:/sbin',
    UV_CACHE_DIR: join(cacheDir, 'uv'),
    npm_config_cache: join(cacheDir, 'npm'),
    HARNESS_DSH: manifest.id,
    HARNESS_DSH_DIR: install,
  }
  const steps = []
  const run = (name, command, cwd, extra = {}, timeout = 10 * 60_000) => {
    const started = Date.now()
    const result = spawnSync('/usr/bin/env', ['-i', ...Object.entries({ ...env, ...extra }).map(([k, v]) => `${k}=${v}`), '/bin/bash', '-c', command], {
      cwd, encoding: 'utf8', timeout, maxBuffer: 64 * 1024 * 1024,
    })
    const step = {
      name,
      command,
      exit: result.status,
      timedOut: result.error?.code === 'ETIMEDOUT' || result.signal === 'SIGTERM',
      seconds: Math.round((Date.now() - started) / 1000),
      output: tail(`${result.stdout ?? ''}${result.stderr ?? ''}`),
    }
    steps.push(step)
    return step.exit === 0 && !step.timedOut
  }

  const quote = (p) => `'${p.replace(/'/g, `'\\''`)}'`
  let failedAt = null
  const setup = manifest.toolchain?.setup
  if (setup && !run('setup', quote(join(install, setup)), install, {}, setupTimeoutMs)) failedAt = 'setup'
  const doctor = manifest.toolchain?.doctor
  if (!failedAt && doctor && !run('doctor', quote(join(install, doctor)), install)) failedAt = 'doctor'
  const ws = manifest.workspace ?? {}
  if (!failedAt && ws.template && existsSync(join(install, ws.template))) cpSync(join(install, ws.template), workspace, { recursive: true })
  if (!failedAt && ws.init && !run('init', quote(join(install, ws.init)), workspace, { HARNESS_WORKSPACE: workspace })) failedAt = 'init'

  const report = {
    passed: failedAt === null,
    failedAt,
    package: manifest.id,
    platform: `${process.platform}-${process.arch}`,
    at: new Date().toISOString(),
    seconds: steps.reduce((s, x) => s + x.seconds, 0),
    steps,
    workspaceFiles: existsSync(workspace) ? readdirSync(workspace).slice(0, 40) : [],
    root: keep ? root : null,
  }
  if (!keep) rmSync(root, { recursive: true, force: true })
  return report
}
