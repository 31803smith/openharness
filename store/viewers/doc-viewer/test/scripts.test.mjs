// setup.sh, doctor.sh and viewer.sh, run for real against a scratch copy of the package with a PATH
// that holds only what they may use: bash and dirname, plus a `node` and an `npm` the test controls
// (the real node, one too old, or none; an npm that records what it was asked and exits as told).
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { accessSync, chmodSync, constants, copyFileSync, existsSync, mkdirSync, readFileSync, realpathSync, symlinkSync } from 'node:fs'
import { delimiter, join } from 'node:path'
import { after, test } from 'node:test'
import { cleanup, pkg, put, scratch } from './helpers.mjs'

after(cleanup)

const PDFJS_FILES = ['build/pdf.min.mjs', 'build/pdf.worker.min.mjs', 'web/pdf_viewer.mjs', 'web/pdf_viewer.css', 'legacy/build/pdf.min.mjs', 'legacy/web/pdf_viewer.mjs']
const APP_FILES = ['app/index.html', 'app/app.js', 'app/app.css', 'lib/workspace.mjs']

/** Where `name` lives on this machine's PATH. */
function tool(name) {
  for (const dir of String(process.env.PATH).split(delimiter)) {
    const full = join(dir, name)
    try { accessSync(full, constants.X_OK); return full } catch { /* next */ }
  }
  throw new Error(`${name} is not on PATH`)
}

/**
 * A scratch package holding `script` (copied from this package) and a bin directory for PATH.
 * node: 'real' | 'old' | 'none'; npm: an exit code, or null for none.
 */
function sandbox(script, { node = 'real', npm = null } = {}) {
  const root = scratch({}, 'doc-viewer-sh-')
  const dir = join(root, 'pkg')
  mkdirSync(dir)
  copyFileSync(join(pkg, script), join(dir, script))
  chmodSync(join(dir, script), 0o755)
  const bin = join(root, 'bin')
  mkdirSync(bin)
  for (const name of ['bash', 'dirname']) symlinkSync(tool(name), join(bin, name))
  if (node === 'real') symlinkSync(process.execPath, join(bin, 'node'))
  // A node whose `-e` version check fails, as Node 18 fails `>= 20`.
  if (node === 'old') chmodSync(put(bin, 'node', '#!/bin/sh\n[ "$1" = "-e" ] && exit 1\necho "v18.0.0"\n'), 0o755)
  if (npm !== null) chmodSync(put(bin, 'npm', `#!/bin/sh\necho "$*" >> '${join(root, 'npm.log')}'\nexit ${npm}\n`), 0o755)
  const npmCalls = () => (existsSync(join(root, 'npm.log')) ? readFileSync(join(root, 'npm.log'), 'utf8').split('\n').filter(Boolean) : [])
  const run = (env = {}) => {
    // From another directory: each script finds its own.
    const r = spawnSync(join(dir, script), [], { cwd: root, env: { PATH: bin, HOME: root, ...env }, encoding: 'utf8' })
    return { code: r.status, out: r.stdout, err: r.stderr }
  }
  return { root, dir, bin, run, npmCalls }
}

function installPdfjs(dir, { skip = null, version = '9.9.9' } = {}) {
  for (const f of PDFJS_FILES) if (f !== skip) put(dir, `node_modules/pdfjs-dist/${f}`, '')
  put(dir, 'node_modules/pdfjs-dist/package.json', JSON.stringify({ name: 'pdfjs-dist', version }))
}

test('the scripts are executable in the package', () => {
  for (const script of ['setup.sh', 'doctor.sh', 'viewer.sh']) accessSync(join(pkg, script), constants.X_OK)
})

test('setup: no node, or one older than 20, is a miss before npm runs', () => {
  for (const node of ['none', 'old']) {
    const box = sandbox('setup.sh', { node, npm: 0 })
    const r = box.run()
    assert.equal(r.code, 1, node)
    assert.equal(r.out, 'miss node >= 20 on PATH\n', node)
    assert.deepEqual(box.npmCalls(), [], node)
  }
})

test('setup: no npm is a miss', () => {
  const r = sandbox('setup.sh', { npm: null }).run()
  assert.equal(r.code, 1)
  assert.equal(r.out, 'miss npm on PATH\n')
})

test('setup: a failing npm ci stops setup with its exit code', () => {
  const box = sandbox('setup.sh', { npm: 3 })
  const r = box.run()
  assert.equal(r.code, 3)
  assert.equal(r.out, '')
  assert.deepEqual(box.npmCalls(), ['ci --silent --no-audit --no-fund'])
})

test('setup: a pdf.js file missing after npm ci is named', () => {
  const box = sandbox('setup.sh', { npm: 0 })
  installPdfjs(box.dir, { skip: 'legacy/web/pdf_viewer.mjs' })
  const r = box.run()
  assert.equal(r.code, 1)
  assert.equal(r.out, 'miss pdfjs-dist/legacy/web/pdf_viewer.mjs after npm ci\n')
})

test('setup: npm ci from the lockfile, in the package, then the version installed', () => {
  const box = sandbox('setup.sh', { npm: 0 })
  installPdfjs(box.dir)
  const r = box.run()
  assert.equal(r.code, 0, r.err)
  assert.equal(r.out, 'ok   pdf.js 9.9.9 (viewer components, modern and legacy builds)\n')
  assert.deepEqual(box.npmCalls(), ['ci --silent --no-audit --no-fund'])
})

test('doctor: no node, or one older than 20, is a miss', () => {
  for (const node of ['none', 'old']) {
    const r = sandbox('doctor.sh', { node }).run()
    assert.equal(r.code, 1, node)
    assert.equal(r.out, 'miss node >= 20 on PATH\n', node)
  }
})

test('doctor: pdf.js not installed says to run setup', () => {
  const box = sandbox('doctor.sh')
  const r = box.run()
  assert.equal(r.code, 1)
  assert.equal(r.out, 'miss node_modules/pdfjs-dist/build/pdf.min.mjs — run ./setup.sh\n')
  installPdfjs(box.dir, { skip: 'web/pdf_viewer.css' })
  assert.equal(box.run().out, 'miss node_modules/pdfjs-dist/web/pdf_viewer.css — run ./setup.sh\n')
})

test('doctor: a reader file missing means the package is incomplete', () => {
  const box = sandbox('doctor.sh')
  installPdfjs(box.dir)
  for (const f of APP_FILES) if (f !== 'app/app.css') put(box.dir, f, '')
  const r = box.run()
  assert.equal(r.code, 1)
  assert.equal(r.out, 'miss app/app.css — the package is incomplete\n')
})

test('doctor: everything there is one ok line', () => {
  const box = sandbox('doctor.sh')
  installPdfjs(box.dir, { version: '6.3.289' })
  for (const f of APP_FILES) put(box.dir, f, '')
  const r = box.run()
  assert.equal(r.code, 0, r.err)
  assert.equal(r.out, 'ok   pdf.js 6.3.289 and the reader\n')
})

test('viewer.sh: the port and the workspace are required', () => {
  const box = sandbox('viewer.sh')
  const noPort = box.run({ HARNESS_WORKSPACE: box.root })
  assert.equal(noPort.code, 1)
  assert.match(noPort.err, /HARNESS_VIEWER_PORT/)
  const noWorkspace = box.run({ HARNESS_VIEWER_PORT: '4000' })
  assert.equal(noWorkspace.code, 1)
  assert.match(noWorkspace.err, /HARNESS_WORKSPACE/)
})

test('viewer.sh: runs node on the viewer.mjs beside it, from anywhere', () => {
  const box = sandbox('viewer.sh', { node: 'none' })
  chmodSync(put(box.bin, 'node', '#!/bin/sh\necho "node $*"\n'), 0o755)
  const r = box.run({ HARNESS_VIEWER_PORT: '4000', HARNESS_WORKSPACE: box.root })
  assert.equal(r.code, 0, r.err)
  const [word, file] = r.out.trim().split(' ')
  assert.equal(word, 'node')
  assert.equal(realpathSync(join(file, '..')), realpathSync(box.dir))
  assert.match(file, /\/viewer\.mjs$/)
})
