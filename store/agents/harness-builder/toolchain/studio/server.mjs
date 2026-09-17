// Builder Studio: the Harness Builder's pane. One loopback server per Builder workspace.
//
//   GET /                 the Studio page (studio/app/index.html)
//   GET /app/<file>       its script and style
//   GET /state.json       everything the page draws: the build, the brief and decisions as HTML, the
//                         latest check and fresh install, the proofs with their frames, the package tree
//   GET /file/<path>      a file under the workspace's .builder/ (frames, showcase pictures), never outside
//   GET /events           server-sent events: "change" on every burst of changes, ": ping" every 20 s
//
// The page is read per request, so a Studio upgrade needs no restart.
import { createServer } from 'node:http'
import { existsSync, readdirSync, readFileSync, statSync, watch } from 'node:fs'
import { dirname, extname, join, normalize, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { PROOF_IDS, paths, readBuild, readJson } from '../lib/state.mjs'
import { alive } from '../lib/viewer.mjs'

const port = Number(process.env.HARNESS_VIEWER_PORT)
const workspace = resolve(process.env.HARNESS_WORKSPACE)
const host = '127.0.0.1'
const HERE = dirname(fileURLToPath(import.meta.url))
const APP = join(HERE, 'app')
const TOOLCHAIN = dirname(HERE)
const clients = new Set()

let marked = null
try {
  const mod = await import(join(TOOLCHAIN, 'node_modules', 'marked', 'lib', 'marked.esm.js'))
  marked = mod.marked
  marked.setOptions({ gfm: true })
} catch { /* the brief shows as text */ }

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml', '.json': 'application/json',
  '.log': 'text/plain; charset=utf-8', '.md': 'text/markdown; charset=utf-8', '.txt': 'text/plain; charset=utf-8',
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
}

function markdown(file) {
  if (!existsSync(file)) return null
  const text = readFileSync(file, 'utf8')
  if (!text.trim()) return null
  if (!marked) return `<pre>${escapeHtml(text)}</pre>`
  // No raw HTML from the workspace: escape it before markdown renders.
  return marked.parse(text.replace(/</g, '&lt;'))
}

const SKIP = new Set(['node_modules', '.venv', '.conda', '.playwright', 'vendor', '.git', '__pycache__', 'reference', 'upstream'])
function tree(root, depth = 0) {
  if (!existsSync(root)) return []
  let entries = []
  try { entries = readdirSync(root, { withFileTypes: true }) } catch { return [] }
  return entries
    .filter((e) => !SKIP.has(e.name) && !(e.name.startsWith('.') && e.name !== '.gitignore'))
    .sort((a, b) => (a.isDirectory() === b.isDirectory() ? a.name.localeCompare(b.name) : a.isDirectory() ? -1 : 1))
    .slice(0, 200)
    .map((e) => {
      const p = join(root, e.name)
      if (e.isDirectory()) return { name: e.name, dir: true, children: depth < 4 ? tree(p, depth + 1) : [] }
      let size = 0
      let mtime = 0
      try { const s = statSync(p); size = s.size; mtime = s.mtimeMs } catch { /* raced */ }
      return { name: e.name, size, mtime }
    })
}

function state() {
  const p = paths(workspace)
  const build = readBuild(workspace)
  const manifest = readJson(join(p.package, 'harness.json'), null)
  const proofs = {}
  const ids = [...new Set([...PROOF_IDS, ...Object.keys(build.proofs)])]
  for (const id of ids) {
    const proof = build.proofs[id]
    if (!proof) continue
    const dir = join(p.proofs, id)
    const result = readJson(join(dir, 'result.json'), null)
    const activity = readJson(join(dir, 'activity.json'), null)
    const frames = (result?.frames ?? activity?.frames ?? []).filter((f) => f.file).map((f) => ({ ...f, url: `/file/${relative(p.builder, join(workspace, f.file)).split(sep).join('/')}` }))
    proofs[id] = {
      ...proof,
      running: proof.state === 'running' && Boolean(proof.runnerPid) && alive(proof.runnerPid),
      viewerAlive: Boolean(proof.viewer?.pid) && alive(proof.viewer.pid),
      frames,
      finalImage: existsSync(join(dir, 'viewer.png')) ? `/file/proofs/${id}/viewer.png?v=${Math.round(statSync(join(dir, 'viewer.png')).mtimeMs)}` : null,
      activity: activity?.activity?.slice(-12) ?? [],
      seconds: activity?.seconds ?? result?.seconds ?? null,
      result: result ? { exit: result.exit, timedOut: result.timedOut, firstFrameWithContentAt: result.firstFrameWithContentAt, finalMessage: result.finalMessage, verdict: result.verdict } : null,
      review: markdown(join(dir, 'review.md')),
    }
  }
  const showcase = existsSync(p.showcase) ? readdirSync(p.showcase).filter((f) => /\.jpe?g$/.test(f)).map((f) => `/file/showcase/${f}`) : []
  return {
    workspace: { name: workspace.split(sep).pop() },
    build,
    manifest,
    verdict: readJson(p.verdict, null),
    brief: markdown(p.brief),
    decisions: markdown(p.decisions),
    check: readJson(p.check, null),
    fresh: readJson(p.fresh, null),
    proofs,
    showcase,
    tree: tree(p.package),
    now: Date.now(),
  }
}

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://${host}:${port}`)
  if (url.pathname === '/' || url.pathname.startsWith('/app/')) {
    const name = url.pathname === '/' ? 'index.html' : url.pathname.slice('/app/'.length)
    const full = normalize(join(APP, name))
    if (!full.startsWith(APP + sep) || !TYPES[extname(full)] || !existsSync(full)) { res.writeHead(404); res.end('not found'); return }
    res.writeHead(200, { 'content-type': TYPES[extname(full)], 'cache-control': 'no-store' })
    res.end(readFileSync(full))
    return
  }
  if (url.pathname === '/state.json') {
    let body
    try { body = state() } catch (error) { body = { error: error.message } }
    res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' })
    res.end(JSON.stringify(body))
    return
  }
  if (url.pathname === '/events') {
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' })
    res.write(': hello\n\n')
    clients.add(res)
    req.on('close', () => clients.delete(res))
    return
  }
  if (url.pathname.startsWith('/file/')) {
    const builder = paths(workspace).builder
    let rel
    try { rel = decodeURIComponent(url.pathname.slice('/file/'.length)) } catch { res.writeHead(400); res.end('bad request'); return }
    const full = normalize(resolve(builder, rel))
    if (!full.startsWith(builder + sep) || !existsSync(full) || !statSync(full).isFile() || !TYPES[extname(full).toLowerCase()]) { res.writeHead(404); res.end('not found'); return }
    res.writeHead(200, { 'content-type': TYPES[extname(full).toLowerCase()], 'cache-control': 'no-store' })
    res.end(readFileSync(full))
    return
  }
  res.writeHead(404); res.end('not found')
})

let timer = null
function changed(name) {
  const rel = String(name ?? '')
  if (/(^|\/)(node_modules|\.venv|\.conda|\.git|\.playwright|__pycache__)(\/|$)/.test(rel)) return
  if (timer) return
  timer = setTimeout(() => {
    timer = null
    for (const client of clients) client.write('event: change\ndata: {}\n\n')
  }, 400)
}
try { watch(workspace, { recursive: true }, (_e, filename) => changed(filename?.toString())) } catch (error) {
  console.error(`[studio] cannot watch ${workspace}: ${error.message}`)
}
// Runner liveness and elapsed time change without a file changing: a gentle tick keeps them honest.
setInterval(() => { for (const client of clients) client.write('event: tick\ndata: {}\n\n') }, 5000).unref()
setInterval(() => { for (const client of clients) client.write(': ping\n\n') }, 20_000).unref()

server.listen(port, host, () => console.log(`[builder:studio] http://${host}:${port}/ (workspace: ${workspace})`))
