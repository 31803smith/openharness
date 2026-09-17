// viewer.mjs as Harness runs it: `node viewer.mjs` with HARNESS_WORKSPACE and HARNESS_VIEWER_PORT,
// refusing to start without them, and closing cleanly (open streams included) on SIGTERM or SIGINT.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, test } from 'node:test';

const viewer = fileURLToPath(new URL('../viewer.mjs', import.meta.url));
let workspace;
before(async () => {
  workspace = await mkdtemp(join(tmpdir(), 'web-viewer-process-'));
  await writeFile(join(workspace, 'index.html'), '<h1>Hello, process</h1>');
});
after(() => rm(workspace, { recursive: true, force: true }));

const freePort = () => new Promise((resolve) => {
  const probe = createServer().listen(0, '127.0.0.1', () => { const { port } = probe.address(); probe.close(() => resolve(port)); });
});

function start(env) {
  const { HARNESS_WORKSPACE, HARNESS_VIEWER_PORT, ...rest } = process.env;
  const child = spawn(process.execPath, [viewer], { env: { ...rest, ...env }, stdio: ['ignore', 'pipe', 'pipe'] });
  const out = { stdout: '', stderr: '' };
  child.stdout.on('data', (chunk) => { out.stdout += chunk; });
  child.stderr.on('data', (chunk) => { out.stderr += chunk; });
  const exited = new Promise((resolve) => child.on('exit', (code, signal) => resolve({ code, signal, ...out })));
  return { child, out, exited };
}

test('refuses to start without a workspace', async () => {
  const { code, stderr } = await start({ HARNESS_VIEWER_PORT: '4310' }).exited;
  assert.notEqual(code, 0);
  assert.match(stderr, /HARNESS_WORKSPACE is required\./);
});

test('refuses a port that is not a port', async () => {
  for (const port of [undefined, 'abc', '0', '70000', '43.5']) {
    const env = { HARNESS_WORKSPACE: workspace };
    if (port !== undefined) env.HARNESS_VIEWER_PORT = port;
    const { code, stderr } = await start(env).exited;
    assert.notEqual(code, 0, String(port));
    assert.match(stderr, /HARNESS_VIEWER_PORT must be a valid port\./, String(port));
  }
});

for (const signal of ['SIGTERM', 'SIGINT']) {
  test(`serves on the given loopback port and exits cleanly on ${signal}, ending open streams`, async () => {
    const port = await freePort();
    const run = start({ HARNESS_WORKSPACE: workspace, HARNESS_VIEWER_PORT: String(port) });
    const deadline = Date.now() + 10_000;
    while (!run.out.stdout.includes(`[web-viewer] http://127.0.0.1:${port}/`)) {
      assert.ok(Date.now() < deadline, `the viewer did not start: ${run.out.stderr}`);
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    const base = `http://127.0.0.1:${port}`;
    assert.match(await (await fetch(base + '/files/index.html')).text(), /Hello, process/);
    const stream = await fetch(base + '/events');
    const reader = stream.body.getReader();
    await reader.read();
    run.child.kill(signal);
    const { code } = await run.exited;
    assert.equal(code, 0, 'a clean exit, not death by signal');
    const rest = await reader.read().catch(() => ({ done: true }));
    assert.equal(rest.done, true, 'the stream was closed');
  });
}

test('the manifest\'s doctor passes on Node 20 or newer and fails on an older one, run as Harness runs it', async () => {
  const { toolchain } = JSON.parse(await readFile(new URL('../harness.json', import.meta.url), 'utf8'));
  const doctor = (bin) => spawnSync('/bin/sh', ['-c', toolchain.doctor], { env: { PATH: bin }, encoding: 'utf8' }).status;
  assert.equal(doctor(dirname(process.execPath)), 0, `node ${process.version}`);
  const old = join(workspace, 'old-node');
  await mkdir(old);
  const fake = 'Object.defineProperty(process, "versions", { value: { ...process.versions, node: "18.20.4" } })'; // no single quote: it goes inside one
  await writeFile(join(old, 'node'), `#!/bin/sh\nexec '${process.execPath}' --import 'data:text/javascript,${encodeURIComponent(fake)}' "$@"\n`);
  await chmod(join(old, 'node'), 0o755);
  assert.equal(spawnSync(join(old, 'node'), ['-p', 'process.versions.node'], { encoding: 'utf8' }).stdout.trim(), '18.20.4', 'the stand-in reports an old Node');
  assert.equal(doctor(old), 1);
});
