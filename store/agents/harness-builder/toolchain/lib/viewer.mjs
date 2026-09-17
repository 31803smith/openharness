// Run a harness's viewer the way Harness does: its command on a free loopback port, with the
// workspace and package in its environment, detached so it outlives one `builder` call; and find the
// URL the pane would load.
import { spawn } from 'node:child_process'
import { closeSync, existsSync, openSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { createConnection, createServer } from 'node:net'
import { homedir } from 'node:os'
import { extname, join, relative } from 'node:path'
import { readManifest } from './materialize.mjs'

export function freePort() {
  return new Promise((resolve, reject) => {
    const server = createServer()
    server.unref()
    server.on('error', reject)
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address()
      server.close(() => resolve(port))
    })
  })
}

export function portOpen(port, host = '127.0.0.1') {
  return new Promise((resolve) => {
    const socket = createConnection({ port, host })
    socket.setTimeout(800)
    socket.once('connect', () => { socket.destroy(); resolve(true) })
    socket.once('timeout', () => { socket.destroy(); resolve(false) })
    socket.once('error', () => resolve(false))
  })
}

export async function waitForPort(port, timeoutMs = 60_000) {
  const until = Date.now() + timeoutMs
  while (Date.now() < until) {
    if (await portOpen(port)) return true
    await new Promise((r) => setTimeout(r, 300))
  }
  return false
}

/** Installed packages on this machine (~/.harness/dsh/installed.json), by id. */
export function installedPackages(home = homedir()) {
  try {
    const rows = JSON.parse(readFileSync(join(home, '.harness', 'dsh', 'installed.json'), 'utf8'))
    return new Map(rows.map((row) => [row.id, row]))
  } catch {
    return new Map()
  }
}

/**
 * Where the viewer runs and what it runs: the package's own `viewer.command`, or, for `viewer.use`,
 * the installed viewer package's command in that package's directory. The harness may narrow the
 * url and artifactExtensions of a viewer it uses.
 */
export function resolveViewer(pkg, { installed = installedPackages() } = {}) {
  const manifest = readManifest(pkg)
  const viewer = manifest.viewer
  if (!viewer) return null
  if (viewer.use) {
    const row = installed.get(viewer.use)
    if (!row) return { error: `${viewer.use} is not installed on this machine: harness dsh install ${viewer.use}` }
    const shared = readManifest(row.dir).viewer ?? {}
    return {
      dir: row.dir,
      command: shared.command,
      url: viewer.url ?? shared.url,
      artifactExtensions: viewer.artifactExtensions ?? shared.artifactExtensions ?? [],
      env: { HARNESS_VIEWER: viewer.use, HARNESS_VIEWER_DIR: row.dir },
      manifest,
    }
  }
  return { dir: pkg, command: viewer.command, url: viewer.url, artifactExtensions: viewer.artifactExtensions ?? [], env: {}, manifest }
}

/** The artifact the pane would open: the verdict's, else the newest file with a declared extension. */
export function currentArtifact(workspace, extensions = []) {
  try {
    const verdict = JSON.parse(readFileSync(join(workspace, '.harness', 'verdict.json'), 'utf8'))
    if (verdict?.artifact && existsSync(join(workspace, verdict.artifact))) return verdict.artifact
  } catch { /* no verdict yet */ }
  if (!extensions.length) return ''
  let newest = null
  const walk = (dir, depth) => {
    let entries = []
    try { entries = readdirSync(dir, { withFileTypes: true }) } catch { return }
    for (const e of entries) {
      if (e.name.startsWith('.') || e.name === 'node_modules') continue
      const p = join(dir, e.name)
      if (e.isDirectory()) { if (depth < 6) walk(p, depth + 1); continue }
      if (!extensions.includes(extname(e.name).toLowerCase())) continue
      const mtime = statSync(p).mtimeMs
      if (!newest || mtime > newest.mtime) newest = { path: p, mtime }
    }
  }
  walk(workspace, 0)
  return newest ? relative(workspace, newest.path) : ''
}

export function viewerUrl(template, port, artifact) {
  return template.replace(/\$\{port\}/g, String(port)).replace(/\$\{artifact\}/g, encodeURIComponent(artifact ?? ''))
}

/** Start the viewer detached; resolves once its port is open. */
export async function startViewer(pkg, workspace, { logFile, env: extraEnv = {} } = {}) {
  const resolved = resolveViewer(pkg)
  if (!resolved) return { error: 'the harness declares no viewer' }
  if (resolved.error) return resolved
  const port = await freePort()
  const command = existsSync(join(resolved.dir, resolved.command)) && !/[\s;&|<>$`'"\\]/.test(resolved.command)
    ? `'${join(resolved.dir, resolved.command).replace(/'/g, `'\\''`)}'`
    : resolved.command
  const out = logFile ? openSync(logFile, 'a') : 'ignore'
  const child = spawn('/bin/bash', ['-c', `exec ${command}`], {
    cwd: resolved.dir,
    detached: true,
    stdio: ['ignore', out, out],
    env: {
      ...process.env,
      ...extraEnv,
      ...resolved.env,
      HARNESS_VIEWER_PORT: String(port),
      HARNESS_WORKSPACE: workspace,
      HARNESS_DSH: resolved.manifest.id,
      HARNESS_DSH_DIR: pkg,
    },
  })
  child.unref()
  if (typeof out === 'number') closeSync(out)
  const up = await waitForPort(port, 90_000)
  if (!up) {
    try { process.kill(-child.pid, 'SIGTERM') } catch { /* already gone */ }
    return { error: `the viewer did not open port ${port} within 90 s (see ${logFile ?? 'its output'})` }
  }
  const artifact = currentArtifact(workspace, resolved.artifactExtensions)
  return { port, pid: child.pid, url: viewerUrl(resolved.url, port, artifact), urlTemplate: resolved.url, artifactExtensions: resolved.artifactExtensions }
}

export function stopViewer(pid) {
  if (!pid) return false
  try { process.kill(-pid, 'SIGTERM'); return true } catch { /* not a group leader, or gone */ }
  try { process.kill(pid, 'SIGTERM'); return true } catch { return false }
}

export function alive(pid) {
  if (!pid) return false
  try { process.kill(pid, 0); return true } catch { return false }
}
