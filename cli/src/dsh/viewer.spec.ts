import { afterEach, describe, expect, it } from 'vitest'
import { EventEmitter } from 'node:events'
import type { ChildProcess } from 'node:child_process'
import type { InstalledDsh } from './installed.js'
import { DshViewerManager, buildViewerUrl } from './viewer.js'

function fakeChild(): ChildProcess & { exitWith: (code: number) => void } {
  const child = new EventEmitter() as ChildProcess & { exitWith: (code: number) => void }
  Object.assign(child, {
    // No pid: killProcessGroup returns early instead of signalling a real process group.
    pid: undefined,
    stdout: new EventEmitter(),
    stderr: new EventEmitter(),
    exitWith: (code: number) => child.emit('exit', code, null),
  })
  return child
}

function dsh(viewer: NonNullable<InstalledDsh['manifest']['viewer']>): InstalledDsh {
  return {
    id: 'acme/thing', dir: '/i/acme/thing', realDir: '/i/acme/thing', source: '', ref: null, commit: null,
    linked: false, installedAt: 0,
    manifest: { spec: 1, id: 'acme/thing', name: 'Thing', engine: 'claude', viewer },
  }
}

describe('buildViewerUrl', () => {
  it('fills the port and url-encodes the artifact per segment', () => {
    expect(buildViewerUrl('http://127.0.0.1:${port}/?file=${artifact}', 4790, 'models/my part.step'))
      .toBe('http://127.0.0.1:4790/?file=models/my%20part.step')
    expect(buildViewerUrl('http://127.0.0.1:${port}/', 4790, null)).toBe('http://127.0.0.1:4790/')
    expect(buildViewerUrl('http://127.0.0.1:${port}/?file=${artifact}', 1, null)).toBe('http://127.0.0.1:1/?file=')
  })
})

describe('DshViewerManager', () => {
  let manager: DshViewerManager | null = null
  afterEach(async () => { await manager?.stopAll(); manager = null })

  function setup(opts: { portUp?: boolean; now?: () => number } = {}) {
    const spawned: Array<{ child: ReturnType<typeof fakeChild>; env: Record<string, string>; cwd: string }> = []
    const urls: Array<string | null> = []
    manager = new DshViewerManager({
      onUrl: (_agentId, url) => urls.push(url),
      freePort: async () => 4790 + spawned.length,
      waitForPort: async () => opts.portUp ?? true,
      spawn: ((_script: string, o: { cwd: string; env?: Record<string, string> }) => {
        const child = fakeChild()
        spawned.push({ child, env: o.env ?? {}, cwd: o.cwd })
        return child
      }) as typeof import('./shell.js').spawnDshCommand,
      now: opts.now,
    })
    return { spawned, urls }
  }

  it('publishes a URL once the port answers, with the env the contract promises', async () => {
    const { spawned, urls } = setup()
    await manager!.start('a1', dsh({ command: 'toolchain/viewer.sh', url: 'http://127.0.0.1:${port}/' }), '/ws')
    expect(spawned).toHaveLength(1)
    expect(spawned[0].cwd).toBe('/i/acme/thing')
    expect(spawned[0].env).toMatchObject({
      HARNESS_DSH: 'acme/thing', HARNESS_DSH_DIR: '/i/acme/thing', HARNESS_WORKSPACE: '/ws', HARNESS_VIEWER_PORT: '4790',
    })
    expect(urls).toEqual(['http://127.0.0.1:4790/'])
    expect(manager!.url('a1')).toBe('http://127.0.0.1:4790/')
  })

  it('is idempotent for the same agent, DSH and workspace', async () => {
    const { spawned } = setup()
    const d = dsh({ command: 'v', url: 'http://127.0.0.1:${port}/' })
    await manager!.start('a1', d, '/ws')
    await manager!.start('a1', d, '/ws')
    expect(spawned).toHaveLength(1)
  })

  it('republishes when the verdict names an artifact, and only when the URL changes', async () => {
    const { urls } = setup()
    await manager!.start('a1', dsh({ command: 'v', url: 'http://127.0.0.1:${port}/?file=${artifact}' }), '/ws')
    manager!.setVerdictArtifact('a1', 'models/a.step')
    manager!.setVerdictArtifact('a1', 'models/a.step')
    manager!.setVerdictArtifact('a1', null)
    expect(urls).toEqual([
      'http://127.0.0.1:4790/?file=',
      'http://127.0.0.1:4790/?file=models/a.step',
      'http://127.0.0.1:4790/?file=',
    ])
  })

  it('publishes null when the port never answers, and stops the child', async () => {
    const { urls } = setup({ portUp: false })
    await manager!.start('a1', dsh({ command: 'v', url: 'http://127.0.0.1:${port}/' }), '/ws')
    expect(urls).toEqual([])
    expect(manager!.url('a1')).toBeNull()
  })

  it('restarts a viewer that exits, then gives up after four exits in a minute', async () => {
    let clock = 0
    const { spawned, urls } = setup({ now: () => clock })
    await manager!.start('a1', dsh({ command: 'v', url: 'http://127.0.0.1:${port}/' }), '/ws')
    expect(urls).toEqual(['http://127.0.0.1:4790/'])
    spawned[0].child.exitWith(1)
    expect(urls.at(-1)).toBeNull()
    // The restart is scheduled with a real timer (1s); the fourth exit inside the window gives up.
    for (let i = 0; i < 3; i++) {
      await new Promise((resolve) => setTimeout(resolve, 1_100 * 2 ** i))
      expect(spawned).toHaveLength(i + 2)
      clock += 1_000
      spawned[i + 1].child.exitWith(1)
    }
    await new Promise((resolve) => setTimeout(resolve, 200))
    expect(spawned).toHaveLength(4)
  }, 15_000)

  it('stops publish null and forgets the agent', async () => {
    const { urls } = setup()
    await manager!.start('a1', dsh({ command: 'v', url: 'http://127.0.0.1:${port}/' }), '/ws')
    await manager!.stop('a1')
    expect(urls.at(-1)).toBeNull()
    expect(manager!.url('a1')).toBeNull()
  })
})
