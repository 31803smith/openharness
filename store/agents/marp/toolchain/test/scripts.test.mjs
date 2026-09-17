// setup.sh, doctor.sh, init-workspace.sh and viewer.sh, run for real by /bin/bash against a scratch
// install whose PATH is only stub commands and the few coreutils the scripts use: every ok, warn and
// miss line is reached without npm, a browser or a network.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const TOOLCHAIN = fileURLToPath(new URL('..', import.meta.url))
const COREUTILS = ['dirname', 'sed', 'basename', 'mkdir']
// A bash line tracer's hooks (BASH_ENV sourcing a DEBUG trap that appends to SHCOV_OUT), passed through when set.
const TRACER = Object.fromEntries(['BASH_ENV', 'SHCOV_OUT'].filter((k) => process.env[k]).map((k) => [k, process.env[k]]))

function sandbox(t) {
  const root = mkdtempSync(join(tmpdir(), 'marp-scripts-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const install = join(root, 'install')
  mkdirSync(join(install, 'toolchain'), { recursive: true })
  // Linked, not copied: $0 still names the scratch install, and a line tracer can map back to the source.
  for (const script of ['doctor.sh', 'setup.sh', 'init-workspace.sh', 'viewer.sh']) symlinkSync(join(TOOLCHAIN, script), join(install, 'toolchain', script))
  const bin = join(root, 'bin')
  const home = join(root, 'home')
  const apps = join(root, 'Applications')
  for (const dir of [bin, home, apps]) mkdirSync(dir)
  for (const name of COREUTILS) symlinkSync(['/bin', '/usr/bin'].map((d) => join(d, name)).find((p) => existsSync(p)), join(bin, name))
  const calls = join(root, 'calls.log')
  writeFileSync(calls, '')
  const box = {
    root, install, bin, home, apps,
    file(rel, body = '') { const full = join(install, rel); mkdirSync(dirname(full), { recursive: true }); writeFileSync(full, body); return full },
    stub(name, body = '', where = bin) {
      const full = join(where, name)
      mkdirSync(where, { recursive: true })
      writeFileSync(full, `#!/bin/bash\necho "${name} $*" >> "$CALLS"\n${body}\n`)
      chmodSync(full, 0o755)
      return full
    },
    run(script, { cwd = install, env = {} } = {}) {
      const r = spawnSync('/bin/bash', [join(install, 'toolchain', script)], {
        cwd, encoding: 'utf8', timeout: 30_000,
        env: { PATH: bin, HOME: home, CALLS: calls, MARP_APPLICATIONS_DIR: apps, ...TRACER, ...env },
      })
      return { code: r.status, lines: r.stdout.split('\n').filter(Boolean), stderr: r.stderr }
    },
    logged: () => readFileSync(calls, 'utf8').split('\n').filter(Boolean),
  }
  return box
}

/** A machine with everything: claude, node 22, the installed toolchain, the pane, Chrome. */
function healthy(t) {
  const box = sandbox(t)
  box.stub('claude')
  box.stub('node', 'case "$1" in --version) echo v22.11.0 ;; -p) echo 4.1.0 ;; esac')
  mkdirSync(join(box.install, 'toolchain/node_modules/@marp-team/marp-core'), { recursive: true })
  chmodSync(box.file('toolchain/node_modules/.bin/marp'), 0o755)
  for (const f of ['toolchain/viewer.mjs', 'toolchain/viewer/index.html', 'toolchain/viewer/app.js']) box.file(f)
  mkdirSync(join(box.apps, 'Google Chrome.app'))
  return box
}

const OK = [
  'ok   claude on PATH',
  'ok   node 22.11.0',
  'ok   marp-core 4.1.0',
  'ok   marp-cli (PDF, PPTX and HTML export)',
  'ok   viewer pane (slide, grid, presenter, present)',
  'ok   browser for PDF/PPTX export: Google Chrome.app',
]

test('doctor: a machine with everything is ready', (t) => {
  const r = healthy(t).run('doctor.sh')
  assert.deepEqual(r.lines, OK)
  assert.equal(r.code, 0)
})

test('doctor: claude from the installer, outside PATH, counts', (t) => {
  const box = healthy(t)
  rmSync(join(box.bin, 'claude'))
  box.stub('claude', '', join(box.home, '.local', 'bin'))
  assert.deepEqual(box.run('doctor.sh').lines[0], 'ok   claude on PATH')
  rmSync(join(box.home, '.local'), { recursive: true })
  const r = box.run('doctor.sh')
  assert.equal(r.lines[0], 'miss claude not found — install Claude Code: https://claude.ai/install')
  assert.equal(r.code, 1)
})

test('doctor: node missing, too old, or saying something that is not a version', (t) => {
  const box = healthy(t)
  for (const [version, line] of [['v16.20.2', 'miss node 16.20.2 is older than 18 (brew install node)'], ['nightly', 'miss node nightly is older than 18 (brew install node)']]) {
    box.stub('node', `case "$1" in --version) echo ${version} ;; -p) echo 4.1.0 ;; esac`)
    const r = box.run('doctor.sh')
    assert.equal(r.lines[1], line)
    assert.equal(r.code, 1)
  }
  rmSync(join(box.bin, 'node'))
  const r = box.run('doctor.sh')
  assert.deepEqual(r.lines.slice(1, 3), ['miss node not found (brew install node)', 'ok   marp-core present'], 'the version needs node; the install is still there')
  assert.equal(r.code, 1)
})

test('doctor: no toolchain is a miss, no marp-cli only a warning, an incomplete pane a miss', (t) => {
  const box = healthy(t)
  rmSync(join(box.install, 'toolchain/node_modules/.bin/marp'))
  let r = box.run('doctor.sh')
  assert.equal(r.lines[3], 'warn marp-cli missing — decks show live but do not export')
  assert.equal(r.code, 0)
  rmSync(join(box.install, 'toolchain/node_modules'), { recursive: true })
  r = box.run('doctor.sh')
  assert.equal(r.lines[2], 'miss marp toolchain not installed — run toolchain/setup.sh')
  assert.equal(r.code, 1)
  for (const f of ['toolchain/viewer/app.js', 'toolchain/viewer/index.html', 'toolchain/viewer.mjs']) {
    const box2 = healthy(t)
    rmSync(join(box2.install, f))
    const r2 = box2.run('doctor.sh')
    assert.equal(r2.lines[4], 'miss toolchain/viewer/ is incomplete — reinstall the harness', f)
    assert.equal(r2.code, 1)
  }
})

test('doctor: each browser marp-cli can export with, or a warning when there is none', (t) => {
  for (const app of ['Chromium.app', 'Microsoft Edge.app', 'Brave Browser.app']) {
    const box = healthy(t)
    rmSync(join(box.apps, 'Google Chrome.app'), { recursive: true })
    mkdirSync(join(box.apps, app))
    assert.equal(box.run('doctor.sh').lines[5], `ok   browser for PDF/PPTX export: ${app}`)
  }
  const box = healthy(t)
  rmSync(join(box.apps, 'Google Chrome.app'), { recursive: true })
  let r = box.run('doctor.sh')
  assert.equal(r.lines[5], 'warn no Chrome/Chromium/Edge — HTML export only, no PDF or PPTX')
  assert.equal(r.code, 0, 'a warning is not a miss')
  box.stub('google-chrome')
  assert.equal(box.run('doctor.sh').lines[5], 'ok   browser for PDF/PPTX export: google-chrome')
  box.stub('chromium')
  assert.equal(box.run('doctor.sh').lines[5], 'ok   browser for PDF/PPTX export: chromium')
})

test('setup: npm ci from the lockfile, npm install without one, and the version it got', (t) => {
  const box = sandbox(t)
  box.stub('node', 'echo 4.1.0')
  box.stub('npm')
  box.file('toolchain/package-lock.json', '{}')
  let r = box.run('setup.sh')
  assert.deepEqual([r.code, r.lines], [0, ['ok   marp toolchain 4.1.0']])
  rmSync(join(box.install, 'toolchain/package-lock.json'))
  r = box.run('setup.sh')
  assert.equal(r.code, 0)
  assert.deepEqual(box.logged().filter((c) => c.startsWith('npm')), ['npm ci --no-audit --no-fund', 'npm install --no-audit --no-fund'])
})

test('setup: no node is a miss, and a failed install fails setup', (t) => {
  const box = sandbox(t)
  let r = box.run('setup.sh')
  assert.deepEqual([r.code, r.lines], [1, ['miss node — install Node 18 or newer (brew install node)']])
  box.stub('node', 'echo 4.1.0')
  box.stub('npm', 'exit 1')
  r = box.run('setup.sh')
  assert.notEqual(r.code, 0)
  assert.deepEqual(r.lines, [], 'no ok line after a failed npm')
})

test('init-workspace: makes the folders and seeds the verdict, even when the check fails', (t) => {
  const box = sandbox(t)
  const ws = join(box.root, 'ws')
  mkdirSync(ws)
  box.stub('node', 'exit 1')
  const r = box.run('init-workspace.sh', { cwd: ws, env: { HARNESS_DSH_DIR: box.install } })
  assert.equal(r.code, 0, r.stderr)
  assert.ok(existsSync(join(ws, '.harness')) && existsSync(join(ws, 'assets')))
  assert.deepEqual(box.logged(), [`node ${box.install}/toolchain/check.mjs deck.md`])
})

test('init-workspace: needs the install dir', (t) => {
  const box = sandbox(t)
  const r = box.run('init-workspace.sh', { cwd: box.root })
  assert.equal(r.code, 1)
  assert.match(r.stderr, /HARNESS_DSH_DIR: HARNESS_DSH_DIR is required/)
})

test('viewer.sh: needs a port and a workspace, then becomes the node server', (t) => {
  const box = sandbox(t)
  box.stub('node', 'echo "server $HARNESS_VIEWER_PORT $HARNESS_WORKSPACE"')
  let r = box.run('viewer.sh', { env: { HARNESS_WORKSPACE: '/Users/example/deck' } })
  assert.equal(r.code, 1)
  assert.match(r.stderr, /HARNESS_VIEWER_PORT is required/)
  r = box.run('viewer.sh', { env: { HARNESS_VIEWER_PORT: '4100' } })
  assert.equal(r.code, 1)
  assert.match(r.stderr, /HARNESS_WORKSPACE is required/)
  r = box.run('viewer.sh', { env: { HARNESS_VIEWER_PORT: '4100', HARNESS_WORKSPACE: '/Users/example/deck' } })
  assert.deepEqual([r.code, r.lines], [0, ['server 4100 /Users/example/deck']])
  assert.deepEqual(box.logged(), [`node ${box.install}/toolchain/viewer.mjs`])
})
