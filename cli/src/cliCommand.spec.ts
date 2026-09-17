import { spawn, spawnSync } from 'child_process'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'fs'
import { createServer } from 'node:http'
import type { AddressInfo } from 'node:net'
import { tmpdir } from 'os'
import { join } from 'path'
import { fileURLToPath } from 'url'
import { afterEach, describe, expect, it } from 'vitest'

const CLI_ROOT = fileURLToPath(new URL('..', import.meta.url))
const CLI_SOURCE = join(CLI_ROOT, 'src', 'cli.ts')
const TSX = join(CLI_ROOT, 'node_modules', 'tsx', 'dist', 'cli.mjs')
const dirs: string[] = []

afterEach(() => { for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }) })

/** A throwaway HOME for one CLI run; every path the CLI writes is under it. */
function freshRoot(): string {
  const root = mkdtempSync(join(tmpdir(), 'harness-cli-command-'))
  dirs.push(root)
  return root
}

function envFor(root: string, extra: NodeJS.ProcessEnv = {}): NodeJS.ProcessEnv {
  return {
    ...process.env,
    HOME: root,
    HARNESS_AUTH_DIR: join(root, 'auth'),
    ADAPTER_DATA_DIR: join(root, 'data'),
    ADAPTER_CLI_DIR: join(root, 'cli'),
    ADAPTER_COMPUTER_ID_FILE: join(root, 'computer-id'),
    ADAPTER_UPDATE_DISABLE: 'true',
    ...extra,
  }
}

function run(...args: string[]) {
  return spawnSync(process.execPath, [TSX, CLI_SOURCE, ...args], { cwd: CLI_ROOT, encoding: 'utf8', env: envFor(freshRoot()) })
}

/** The same run, without blocking this process: a test that also SERVES the CLI something (a manifest on
 *  the loopback) has to keep its own event loop free while the child asks for it. */
function runAsync(root: string, args: string[], extra: NodeJS.ProcessEnv): Promise<{ status: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [TSX, CLI_SOURCE, ...args], { cwd: CLI_ROOT, env: envFor(root, extra), stdio: ['ignore', 'pipe', 'pipe'] })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (chunk: Buffer) => { stdout += chunk.toString() })
    child.stderr.on('data', (chunk: Buffer) => { stderr += chunk.toString() })
    child.on('close', (status) => resolve({ status, stdout, stderr }))
  })
}

/** A signed-in computer: `start` refuses without one, before it looks at anything else. */
function seedSession(root: string): void {
  mkdirSync(join(root, 'auth'), { recursive: true })
  writeFileSync(join(root, 'auth', 'session.json'), JSON.stringify({
    version: 1, accessToken: 'tok', refreshToken: 'refresh', expiresAt: Date.now() + 3_600_000,
    autonomousEnv: 'prod', computerId: 'a'.repeat(32), machineId: 'm_seeded', updatedAt: Date.now(),
  }))
}

/** A daemon that is up, as `start` sees one: a pid file naming a live process — this one. */
function seedRunningDaemon(root: string): void {
  mkdirSync(join(root, 'data'), { recursive: true })
  writeFileSync(join(root, 'data', 'adapter.pid'), `${process.pid}\n`)
}

describe('CLI login/start command contract', () => {
  it('does not start or open SSO when start has no saved session', () => {
    const result = run('start')

    expect(result.status).toBe(1)
    expect(result.stderr).toContain('Not signed in. Run: harness login')
    expect(result.stdout).not.toContain('Sign in to Harness in your browser')
  })

  it('rejects the removed join command with the two-step migration', () => {
    const result = run('join')

    expect(result.status).toBe(1)
    expect(result.stderr).toContain('`harness join` has been removed.')
    expect(result.stderr).toContain('`harness login`, then `harness start`')
  })

  it('no longer has an analytics command (usage metering upload was removed)', () => {
    const result = run('analytics')

    expect(result.status).toBe(1)
    expect(result.stderr).toContain('Unknown command: analytics')
  })

  it('returns a nonzero status for an unknown command', () => {
    const result = run('not-a-command')

    expect(result.status).toBe(1)
    expect(result.stderr).toContain('Unknown command: not-a-command')
  })
})

describe('start --repair beside a running daemon', () => {
  // The managed runtimes live beside the bundle, not in it, and the daemon reads `current-grid` on every
  // resolve — so a grid laid down here is the one its next spawn runs, with no restart. `--repair` is the
  // one place a person WATCHES that provisioning; beside a live daemon it used to exit at "already
  // running" before reaching it, and the only way to follow a new pin was a restart.
  const key = `${process.platform}-${process.arch}`

  /** Serves a grid manifest that pins 9.9.9 to an archive nobody can fetch: the download is refused at
   *  once, which is a best-effort skip inside ensureManagedGrid — and the "installing" line has already
   *  said the step was reached, which is the whole of what this contract is about. */
  async function withManifest<T>(body: (url: string) => Promise<T>): Promise<T> {
    const server = createServer((_req, res) => {
      res.setHeader('content-type', 'application/json')
      res.end(JSON.stringify({ grid: { [key]: {
        version: '9.9.9', url: 'https://127.0.0.1:1/grid.tar.gz', sha256: '0'.repeat(64), archiveRoot: `grid-9.9.9-${key}`,
      } } }))
    })
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
    try {
      return await body(`http://127.0.0.1:${(server.address() as AddressInfo).port}/metadata.json`)
    } finally {
      await new Promise<void>((resolve) => server.close(() => resolve()))
    }
  }

  const noNode = 'http://127.0.0.1:9/metadata.json'   // refused at once: the Node runtime is not what is under test

  it('provisions the managed grid for the daemon that is up, and still leaves the daemon itself alone', async () => {
    const root = freshRoot()
    seedSession(root)
    seedRunningDaemon(root)
    const result = await withManifest((manifest) => runAsync(root, ['start', '--repair'], {
      ADAPTER_RUNTIME_DIR: join(root, 'runtime'), ADAPTER_RUNTIME_METADATA_URL: noNode, ADAPTER_GRID_RUNTIME_METADATA_URL: manifest,
    }))

    expect(result.status).toBe(0)
    expect(result.stdout).toContain(`installing the Harness grid runtime (9.9.9, ${key})`)
    expect(result.stdout).toContain('already running')
    expect(result.stdout).not.toContain('updated to v')   // no bundle staging beside a live daemon
  }, 20_000)

  it('a plain start beside a running daemon touches nothing', async () => {
    const root = freshRoot()
    seedSession(root)
    seedRunningDaemon(root)
    const result = await withManifest((manifest) => runAsync(root, ['start'], {
      ADAPTER_RUNTIME_DIR: join(root, 'runtime'), ADAPTER_RUNTIME_METADATA_URL: noNode, ADAPTER_GRID_RUNTIME_METADATA_URL: manifest,
    }))

    expect(result.status).toBe(0)
    expect(result.stdout).toContain('already running')
    expect(result.stdout).not.toContain('installing the Harness grid runtime')
  }, 20_000)
})
