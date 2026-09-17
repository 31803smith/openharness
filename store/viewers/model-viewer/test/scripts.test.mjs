// setup.sh, doctor.sh and viewer.sh, run for real against a scratch copy of the package with only the
// tools each case allows on PATH: Node (the real one, one that is too old, or none), and an npm stub
// that installs as much as the case says and logs what it was asked.
//
//   npm test
import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { after, describe, test } from 'node:test'
import { freePort, packageDir, sleep } from './helpers.mjs'

const roots = []
after(() => { for (const root of roots) rmSync(root, { recursive: true, force: true }) })

function systemTool(name) {
  const found = ['/bin', '/usr/bin'].map((dir) => join(dir, name)).find((path) => existsSync(path))
  assert.ok(found, `${name} is on this machine`)
  return found
}

const NPM = `#!/bin/sh
echo "$*" >> "$NPM_LOG"
case "$1" in
  ci)
    [ "$NPM_CI" = fail ] && { echo "npm ERR! ci failed" >&2; exit 1; }
    [ "$NPM_CI" = nothing ] && exit 0
    /bin/mkdir -p node_modules/three/build node_modules/three/examples/jsm/loaders
    echo '{ "version": "0.186.0" }' > node_modules/three/package.json
    : > node_modules/three/build/three.module.js
    [ "$NPM_CI" = no-loader ] && exit 0
    : > node_modules/three/examples/jsm/loaders/GLTFLoader.js ;;
  run)
    [ "$NPM_SMOKE" = fail ] && { echo "smoke failed" >&2; exit 1; }
    echo "smoke ok" ;;
esac
exit 0
`

/**
 * `script` copied into an empty package folder, with a bin folder holding bash and dirname plus
 * `node` ('real', 'old' or none) and the npm stub (or none). `files` are created in the package.
 */
function sandbox(script, { node = 'real', npm = true, files = [] } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'model-viewer-scripts-'))
  roots.push(root)
  const pkg = join(root, 'pkg'), bin = join(root, 'bin')
  mkdirSync(pkg); mkdirSync(bin)
  copyFileSync(join(packageDir, script), join(pkg, script))
  chmodSync(join(pkg, script), 0o755)
  for (const tool of ['bash', 'dirname']) symlinkSync(systemTool(tool), join(bin, tool))
  if (node === 'real') symlinkSync(process.execPath, join(bin, 'node'))
  if (node === 'old') { writeFileSync(join(bin, 'node'), '#!/bin/sh\nexit 1\n'); chmodSync(join(bin, 'node'), 0o755) }
  if (npm) { writeFileSync(join(bin, 'npm'), NPM); chmodSync(join(bin, 'npm'), 0o755) }
  for (const [rel, body] of files) { mkdirSync(dirname(join(pkg, rel)), { recursive: true }); writeFileSync(join(pkg, rel), body) }
  const log = join(root, 'npm.log')
  const run = (env = {}) => {
    const r = spawnSync(join(pkg, script), [], { env: { PATH: bin, NPM_LOG: log, ...env }, encoding: 'utf8' })
    const npmCalls = existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n') : []
    return { status: r.status, lines: r.stdout.trim().split('\n').filter(Boolean), stderr: r.stderr, npmCalls }
  }
  return { pkg, run }
}

const THREE = [
  ['node_modules/three/package.json', '{ "version": "0.186.0" }'],
  ['node_modules/three/build/three.module.js', ''],
  ['node_modules/three/examples/jsm/loaders/GLTFLoader.js', ''],
]
const WEB = [['web/index.html', ''], ['web/app.js', '']]

describe('setup.sh', () => {
  test('installs three from the lockfile, runs the smoke test, and says which three it is', () => {
    const r = sandbox('setup.sh').run()
    assert.deepEqual(r.npmCalls, ['ci --silent --no-audit --no-fund', 'run smoke --silent'])
    assert.deepEqual(r.lines, ['smoke ok', 'ok   three 0.186.0 (3D Viewer)'])
    assert.equal(r.status, 0)
  })

  test('refuses without Node 18 or newer, and without npm', () => {
    for (const node of [null, 'old']) {
      const r = sandbox('setup.sh', { node }).run()
      assert.deepEqual(r.lines, ['miss node >= 18 on PATH'], `node: ${node}`)
      assert.equal(r.status, 1)
      assert.deepEqual(r.npmCalls, [], 'nothing is installed')
    }
    const r = sandbox('setup.sh', { npm: false }).run()
    assert.deepEqual(r.lines, ['miss npm on PATH'])
    assert.equal(r.status, 1)
  })

  test('stops when npm ci fails, when it leaves three or its glTF loader out, and when the smoke test fails', () => {
    let r = sandbox('setup.sh').run({ NPM_CI: 'fail' })
    assert.equal(r.status, 1)
    assert.deepEqual(r.lines, [])
    assert.match(r.stderr, /ci failed/)
    r = sandbox('setup.sh').run({ NPM_CI: 'nothing' })
    assert.deepEqual([r.status, r.lines], [1, ['miss three after npm ci']])
    r = sandbox('setup.sh').run({ NPM_CI: 'no-loader' })
    assert.deepEqual([r.status, r.lines], [1, ["miss three's glTF loader after npm ci"]])
    r = sandbox('setup.sh').run({ NPM_SMOKE: 'fail' })
    assert.equal(r.status, 1)
    assert.deepEqual(r.npmCalls, ['ci --silent --no-audit --no-fund', 'run smoke --silent'])
    assert.ok(!r.lines.some((line) => line.startsWith('ok')), 'no ok line after a failed smoke test')
  })
})

describe('doctor.sh', () => {
  test('ready: node, three and the page, one ok line each for the tools', () => {
    const r = sandbox('doctor.sh', { files: [...THREE, ...WEB] }).run()
    assert.deepEqual(r.lines, [`ok   node ${process.version}`, 'ok   three 0.186.0'])
    assert.equal(r.status, 0)
  })

  test('says what is missing: Node (or too old a Node), three or its loader, the page', () => {
    for (const node of [null, 'old']) {
      const r = sandbox('doctor.sh', { node, files: [...THREE, ...WEB] }).run()
      assert.equal(r.lines[0], 'miss node >= 18 on PATH', `node: ${node}`)
      assert.equal(r.status, 1)
    }
    let r = sandbox('doctor.sh', { files: WEB }).run()
    assert.deepEqual([r.status, r.lines.slice(1)], [1, ['miss node_modules/three — run ./setup.sh']])
    r = sandbox('doctor.sh', { files: [THREE[0], THREE[1], ...WEB] }).run()
    assert.deepEqual([r.status, r.lines.slice(1)], [1, ['miss node_modules/three — run ./setup.sh']])
    for (const web of [[WEB[0]], [WEB[1]], []]) {
      r = sandbox('doctor.sh', { files: [...THREE, ...web] }).run()
      assert.deepEqual([r.status, r.lines.slice(1)], [1, ['ok   three 0.186.0', 'miss web/ — the package is incomplete']], JSON.stringify(web))
    }
  })
})

describe('viewer.sh', () => {
  test('needs the port and the workspace Harness passes', () => {
    const script = join(packageDir, 'viewer.sh')
    const env = { PATH: process.env.PATH, HARNESS_VIEWER_PORT: '1', HARNESS_WORKSPACE: tmpdir() }
    for (const missing of ['HARNESS_VIEWER_PORT', 'HARNESS_WORKSPACE']) {
      const r = spawnSync(script, [], { env: { ...env, [missing]: '' }, encoding: 'utf8' })
      assert.equal(r.status, 1, missing)
      assert.match(r.stderr, new RegExp(missing), missing)
    }
  })

  test('runs the server from the package folder, wherever it is started', async () => {
    const workspace = mkdtempSync(join(tmpdir(), 'model-viewer-sh-'))
    roots.push(workspace)
    writeFileSync(join(workspace, 'part.glb'), 'glTF')
    const port = await freePort()
    const child = spawn(join(packageDir, 'viewer.sh'), [], { cwd: tmpdir(), env: { ...process.env, HARNESS_VIEWER_PORT: String(port), HARNESS_WORKSPACE: workspace }, stdio: ['ignore', 'pipe', 'inherit'] })
    const exited = new Promise((resolve) => child.on('exit', (code) => resolve(code)))
    try {
      let out = ''
      child.stdout.on('data', (d) => { out += d })
      const deadline = Date.now() + 15_000
      while (!out.includes('listening') && Date.now() < deadline) await sleep(20)
      assert.match(out, new RegExp(`listening on http://127\\.0\\.0\\.1:${port}/`))
      const s = await (await fetch(`http://127.0.0.1:${port}/api/state`)).json()
      assert.deepEqual(s.models.map((m) => m.path), ['part.glb'])
    } finally {
      child.kill('SIGTERM')
    }
    assert.equal(await exited, 0, 'exec: the signal reaches node, which exits cleanly')
  })
})
