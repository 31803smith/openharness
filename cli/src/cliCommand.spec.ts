import { spawn, spawnSync } from 'child_process'
import { mkdtempSync, rmSync } from 'fs'
import { tmpdir } from 'os'
import { join } from 'path'
import { fileURLToPath } from 'url'
import { afterEach, describe, expect, it } from 'vitest'

const CLI_ROOT = fileURLToPath(new URL('..', import.meta.url))
const CLI_SOURCE = join(CLI_ROOT, 'src', 'cli.ts')
const TSX = join(CLI_ROOT, 'node_modules', 'tsx', 'dist', 'cli.mjs')
const dirs: string[] = []

afterEach(() => { for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }) })

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

/** A long-running command in its own process group, with everything it prints collected as it comes. */
function spawnDetached(args: string[], extra: NodeJS.ProcessEnv) {
  const root = mkdtempSync(join(tmpdir(), 'harness-cli-command-'))
  dirs.push(root)
  const child = spawn(process.execPath, [TSX, CLI_SOURCE, ...args], {
    cwd: CLI_ROOT,
    detached: true,
    env: envFor(root, extra),
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  const output = { text: '' }
  child.stdout.on('data', (chunk: Buffer) => { output.text += chunk.toString() })
  child.stderr.on('data', (chunk: Buffer) => { output.text += chunk.toString() })
  return { child, output }
}

async function waitFor(output: { text: string }, pattern: RegExp, timeoutMs: number): Promise<string> {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (pattern.test(output.text)) return output.text
    await new Promise((r) => setTimeout(r, 100))
  }
  return output.text
}

function run(args: string[], opts: { env?: NodeJS.ProcessEnv; timeout?: number } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'harness-cli-command-'))
  dirs.push(root)
  return spawnSync(process.execPath, [TSX, CLI_SOURCE, ...args], {
    cwd: CLI_ROOT,
    encoding: 'utf8',
    ...(opts.timeout ? { timeout: opts.timeout } : {}),
    env: envFor(root, opts.env),
  })
}

describe('CLI login/start command contract', () => {
  it('starts without a saved session, serving this computer only, and never opens SSO', async () => {
    // The account buys the other machines; everything on THIS computer is served from the daemon over
    // the loopback, so a missing session is not a reason to refuse. A dev-mode start runs the daemon in
    // the foreground, so this holds it on a port of its own until it has said what it is doing, then
    // kills the whole process group (tsx wraps the daemon in a child of its own).
    const port = String(20_000 + Math.floor(Math.random() * 20_000))
    const { child, output } = spawnDetached(['start'], { PORT: port, DISABLE_HOOK_INSTALL: '1' })
    try {
      const said = await waitFor(output, /serving this computer only|Not signed in|Sign in to Harness/, 20_000)
      expect(said).toContain('not signed in — serving this computer only')
      expect(said).not.toContain('Sign in to Harness in your browser')
      expect(said).not.toContain('dialing')   // no backend leg without a session
    } finally {
      try { process.kill(-child.pid!, 'SIGKILL') } catch { /* already gone */ }
    }
  })

  it('rejects the removed join command with the two-step migration', () => {
    const result = run(['join'])

    expect(result.status).toBe(1)
    expect(result.stderr).toContain('`harness join` has been removed.')
    expect(result.stderr).toContain('`harness login`, then `harness start`')
  })

  it('no longer has an analytics command (usage metering upload was removed)', () => {
    const result = run(['analytics'])

    expect(result.status).toBe(1)
    expect(result.stderr).toContain('Unknown command: analytics')
  })

  it('returns a nonzero status for an unknown command', () => {
    const result = run(['not-a-command'])

    expect(result.status).toBe(1)
    expect(result.stderr).toContain('Unknown command: not-a-command')
  })
})
