// The shell scripts Harness runs, on a PATH that holds only what each one needs: doctor.sh says whether
// this machine has a Node that can run the viewer; viewer.sh insists on the port and the workspace, then
// runs the viewer.mjs that sits beside it, whatever the working directory.
//
//   node --test test/*.test.mjs
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, test } from 'node:test'
import { PACKAGE } from './media.mjs'

const roots = []
after(() => { for (const root of roots) rmSync(root, { recursive: true, force: true }) })

/** A bin folder with the named system tools linked in, and `extra` scripts written as executables. */
function bin(tools, extra = {}) {
  const root = mkdtempSync(join(tmpdir(), 'video-viewer-bin-'))
  roots.push(root)
  for (const tool of tools) {
    const found = spawnSync('/bin/sh', ['-c', `command -v ${tool}`], { encoding: 'utf8' }).stdout.trim()
    assert.ok(found, `${tool} is on this machine`)
    symlinkSync(found, join(root, tool))
  }
  for (const [name, body] of Object.entries(extra)) {
    if (body === 'real-node') { symlinkSync(process.execPath, join(root, name)); continue }
    writeFileSync(join(root, name), body)
    chmodSync(join(root, name), 0o755)
  }
  return root
}

const run = (script, { path, env = {}, cwd = tmpdir() }) => {
  const r = spawnSync(script, { cwd, env: { PATH: path, ...env }, encoding: 'utf8' })
  return { code: r.status, out: r.stdout, err: r.stderr }
}

test('doctor.sh: ok with Node 18 or newer, a miss without Node or with an older one', () => {
  const doctor = join(PACKAGE, 'doctor.sh')
  const ok = run(doctor, { path: bin(['bash'], { node: 'real-node' }) })
  assert.deepEqual(ok, { code: 0, out: `ok   node ${process.version}\n`, err: '' })
  const old = run(doctor, { path: bin(['bash'], { node: '#!/bin/sh\n# Node 16: the version check fails\n[ "$1" = "-e" ] && exit 1\necho v16.20.2\n' }) })
  assert.deepEqual(old, { code: 1, out: 'miss node >= 18 on PATH\n', err: '' })
  const none = run(doctor, { path: bin(['bash']) })
  assert.deepEqual(none, { code: 1, out: 'miss node >= 18 on PATH\n', err: '' })
})

test('viewer.sh: the port and the workspace are required; then the viewer beside the script runs', () => {
  const pkg = mkdtempSync(join(tmpdir(), 'video-viewer-pkg-'))
  roots.push(pkg)
  copyFileSync(join(PACKAGE, 'viewer.sh'), join(pkg, 'viewer.sh'))
  chmodSync(join(pkg, 'viewer.sh'), 0o755)
  writeFileSync(join(pkg, 'viewer.mjs'), "console.log(`viewer ${process.env.HARNESS_VIEWER_PORT} ${process.env.HARNESS_WORKSPACE}`)\n")
  const path = bin(['bash', 'dirname'], { node: 'real-node' })
  const script = join(pkg, 'viewer.sh')

  const noPort = run(script, { path, env: { HARNESS_WORKSPACE: '/Users/example/ws' } })
  assert.equal(noPort.code, 1)
  assert.match(noPort.err, /HARNESS_VIEWER_PORT/)
  const noWorkspace = run(script, { path, env: { HARNESS_VIEWER_PORT: '4100' } })
  assert.equal(noWorkspace.code, 1)
  assert.match(noWorkspace.err, /HARNESS_WORKSPACE/)
  assert.equal(noWorkspace.out, '')

  const elsewhere = mkdtempSync(join(tmpdir(), 'video-viewer-cwd-'))
  roots.push(elsewhere)
  mkdirSync(join(elsewhere, 'sub'))
  const started = run(script, { path, cwd: join(elsewhere, 'sub'), env: { HARNESS_VIEWER_PORT: '4100', HARNESS_WORKSPACE: '/Users/example/ws' } })
  assert.deepEqual(started, { code: 0, out: 'viewer 4100 /Users/example/ws\n', err: '' })
})
