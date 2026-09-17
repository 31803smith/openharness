import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { OrchestratorService, type OrchestratorDependencies } from './service.js'
import { OrchestratorError, type Task } from './model.js'
import { orchestratorRequest } from './wire.js'

const id = '0123456789abcdef0123456789abcdef'
const task = (id: string, dependsOn: string[] = [], harness = 'test/cad') => ({ id, title: id, harness, prompt: `Build ${id} and verify it`, dependsOn })
describe('durable orchestrator lifecycle', () => {
  let root: string, service: OrchestratorService, deps: OrchestratorDependencies
  let launches: Parameters<OrchestratorDependencies['create']>[0][]
  let agents: Set<string>, sent: string[], cancelled: string[]
  const tasks = (): Task[] => service.snapshot(id).tasks as Task[]
  const active = async (): Promise<void> => { await vi.waitFor(() => expect(service.snapshot(id).state).toBe('active')) }
  const running = async (taskId: string): Promise<Task> => {
    await vi.waitFor(() => expect(tasks().find(t => t.id === taskId)?.state).toBe('running'))
    return tasks().find(t => t.id === taskId)!
  }
  const start = () => service.start({ id, engine: 'claude', prompt: 'Make something useful', parallelism: 2 })
  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), 'orchestrator-spec-'))
    launches = []; agents = new Set(); sent = []; cancelled = []
    deps = {
      stateDir: join(root, 'state'), workspaceDir: join(root, 'projects'), command: 'harness orchestrator',
      supportsEngine: e => e === 'claude',
      catalog: () => ['cad', 'blender', 'video', 'research'].map(name => ({ id: `test/${name}`, name, description: name, engine: 'claude', viewer: name !== 'research' })),
      create: async input => { launches.push(input); const agentId = `agent-${launches.length}`; agents.add(agentId); return { agentId } },
      send: (_agent, text) => { sent.push(text) }, cancel: agent => { cancelled.push(agent) },
      agent: agent => agents.has(agent) ? { viewerUrl: `http://127.0.0.1:9999/${agent}` } : null,
    }
    service = new OrchestratorService(deps)
  })
  afterEach(() => { service.stop(); rmSync(root, { recursive: true, force: true }) })

  it('starts once, preserves permissions, and rejects a conflicting creation retry', async () => {
    await Promise.all([start(), start()]); await active()
    expect(launches).toHaveLength(1)
    expect(launches[0].bypassPermission).toBe(false)
    expect(launches[0].prompt.length).toBeLessThan(2000)
    expect(readFileSync(join(launches[0].cwd, 'ORCHESTRATOR.md'), 'utf8')).toContain('test/blender')
    await expect(service.start({ id, engine: 'claude', prompt: 'Different' })).rejects.toMatchObject({ code: 'PROJECT_CONFLICT' })
  })
  it('validates every dependency and harness before launching any task', async () => {
    await start(); await active()
    for (const plan of [[task('a', ['missing'])], [task('a', ['b']), task('b', ['a'])], [task('a'), task('b', [], 'missing/harness')]]) {
      expect(() => service.plan(id, plan)).toThrow()
      expect(tasks()).toHaveLength(0)
    }
    expect(launches).toHaveLength(1)
  })
  it('fans out and joins different harnesses using pinned, checksummed copies', async () => {
    await start(); await active()
    service.plan(id, [task('part'), task('research', [], 'test/research'), task('scene', ['part', 'research'], 'test/blender'), task('film', ['scene'], 'test/video')])
    const part = await running('part'), research = await running('research')
    expect(tasks().find(t => t.id === 'scene')!.state).toBe('queued')
    writeFileSync(join(part.cwd, 'part.step'), 'verified CAD v1')
    await service.finish(id, 'part', 1, 'Dimensions checked', ['part.step'])
    writeFileSync(join(part.cwd, 'part.step'), 'unpublished CAD v2')
    await service.finish(id, 'research', 1, 'Use a warm, minimal setting.', [])
    const scene = await running('scene')
    expect(readFileSync(join(scene.cwd, 'inputs/part/part.step'), 'utf8')).toBe('verified CAD v1')
    expect(scene.inputs).toEqual({ part: 1, research: 1 })
    expect(readFileSync(join(scene.cwd, 'ORCHESTRATOR_TASK.md'), 'utf8')).toContain('warm, minimal')
    writeFileSync(join(scene.cwd, 'scene.png'), 'render fixture')
    await service.finish(id, 'scene', 1, 'Render checked', ['scene.png'])
    const film = await running('film')
    expect(readFileSync(join(film.cwd, 'inputs/scene/scene.png'), 'utf8')).toBe('render fixture')
    await service.finish(id, 'film', 1, 'Film ready', [])
    service.complete(id, 'Delivered all outputs')
    expect(service.snapshot(id).state).toBe('completed')
    expect(sent).toHaveLength(4)
    expect(research.agentId).toBeTruthy()
  })
  it('limits parallelism and treats a repeated plan as the same work', async () => {
    await start(); await active()
    const plan = [task('a'), task('b'), task('c')]
    service.plan(id, plan); service.plan(id, plan)
    await running('a'); await running('b')
    expect(launches).toHaveLength(3)
    expect(tasks().find(t => t.id === 'c')!.state).toBe('queued')
    await service.finish(id, 'a', 1, 'done', [])
    await running('c')
    expect(launches).toHaveLength(4)
  })
  it('blocks dependencies after failure and retries in a new workspace', async () => {
    await start(); await active(); service.plan(id, [task('a'), task('b', ['a'])])
    const first = await running('a')
    await service.finish(id, 'a', 1, 'A required tool is missing', [], true)
    expect(tasks().find(t => t.id === 'b')!.state).toBe('blocked')
    service.retry(id, 'a')
    const second = await running('a')
    expect(second.cwd).not.toBe(first.cwd)
    expect(second.attempt).toBe(2)
    await expect(service.finish(id, 'a', 1, 'Late old output', [])).rejects.toMatchObject({ code: 'STALE_ATTEMPT' })
    await service.finish(id, 'a', 2, 'Fixed and verified', [])
    await running('b')
  })
  it('does not mistake idle for success or complete unfinished work', async () => {
    await start(); await active(); service.plan(id, [task('a')]); const a = await running('a')
    service.ingest({ type: 'turn_ended', agentId: a.agentId, payload: {} })
    expect(tasks()[0].state).toBe('running')
    expect(() => service.complete(id, 'done')).toThrow(/Every task/)
  })
  it('rejects path traversal, outside symlinks, directories, and missing artifacts', async () => {
    await start(); await active(); service.plan(id, [task('a')]); const a = await running('a')
    writeFileSync(join(root, 'secret'), 'not a task artifact')
    symlinkSync(join(root, 'secret'), join(a.cwd, 'outside'))
    mkdirSync(join(a.cwd, 'directory'))
    for (const path of ['../secret', join(root, 'secret'), 'outside', 'directory', 'missing']) {
      await expect(service.finish(id, 'a', 1, 'done', [path])).rejects.toThrow()
      expect(tasks()[0].state).toBe('running')
    }
    writeFileSync(join(a.cwd, 'valid.txt'), 'safe')
    await service.finish(id, 'a', 1, 'done', ['valid.txt'])
    expect(tasks()[0].artifacts[0].sha256).toHaveLength(64)
  })
  it('stops only this project, ignores late results, and never kills sessions on close', async () => {
    await start(); await active(); service.plan(id, [task('a'), task('b', ['a'])]); const a = await running('a')
    service.cancel(id)
    expect(cancelled.sort()).toEqual(['agent-1', a.agentId].sort())
    expect(tasks().every(t => t.state === 'cancelled')).toBe(true)
    await expect(service.finish(id, 'a', 1, 'late', [])).rejects.toMatchObject({ code: 'TASK_INACTIVE' })
    service.stop()
    expect(cancelled).toHaveLength(2)
  })
  it('cancels an agent that finishes launching after cancellation', async () => {
    let resolve!: (value: { agentId: string }) => void
    deps.create = () => new Promise(r => { resolve = r })
    await start(); service.cancel(id); resolve({ agentId: 'late-director' })
    await vi.waitFor(() => expect(cancelled).toContain('late-director'))
    expect(service.snapshot(id).state).toBe('cancelled')
  })
  it('refuses blind retry of an uncertain process spawn', async () => {
    await start(); await active()
    deps.create = async () => { throw new OrchestratorError('SPAWN_FAILED', 'tmux timed out') }
    service.plan(id, [task('a')])
    await vi.waitFor(() => expect(tasks()[0].state).toBe('blocked'))
    expect(tasks()[0].uncertain).toBe(true)
    expect(() => service.retry(id, 'a')).toThrow(/uncertain/)
  })
  it('persists transcript and reattaches without launching duplicate agents', async () => {
    await start(); await active(); service.plan(id, [task('a')]); await running('a')
    service.ingest({ type: 'turn_started', agentId: 'agent-1', payload: {} })
    service.ingest({ type: 'text_delta', agentId: 'agent-1', payload: { content: 'Working ' } })
    service.ingest({ type: 'text_delta', agentId: 'agent-1', payload: { content: 'on it.' } })
    service.ingest({ type: 'turn_ended', agentId: 'agent-1', payload: {} })
    service.stop()
    service = new OrchestratorService(deps)
    expect(service.snapshot(id).messages).toEqual(expect.arrayContaining([expect.objectContaining({ role: 'assistant', text: 'Working on it.' })]))
    expect(tasks()[0].agentId).toBe('agent-2')
    expect(launches).toHaveLength(2)
    await service.finish(id, 'a', 1, 'recovered result', [])
    expect(tasks()[0].state).toBe('succeeded')
  })
  it('handles lost chat acknowledgments without sending twice', async () => {
    await start(); await active()
    const messageId = '11111111111111111111111111111111'
    service.chat(id, messageId, 'Make it taller')
    service.chat(id, messageId, 'Make it taller')
    expect(sent).toEqual(['Make it taller'])
    expect(() => service.chat(id, messageId, 'Different message')).toThrow()
  })
  it('tracks real delivery receipts and does not silently resend after restart', async () => {
    await start(); await active()
    const messageId = '22222222222222222222222222222222'
    const send = vi.spyOn(deps, 'send')
    service.chat(id, messageId, 'Make it taller')
    expect(send).toHaveBeenCalledWith('agent-1', 'Make it taller', messageId)
    service.delivery({ deliveryId: messageId, sessionId: 'agent-1', state: 'queued' })
    service.stop(); service = new OrchestratorService(deps)
    expect(service.snapshot(id).messages).toEqual(expect.arrayContaining([expect.objectContaining({ id: messageId, delivery: 'unknown' })]))
    service.chat(id, messageId, 'Make it taller')
    expect(send).toHaveBeenCalledTimes(1)
    service.delivery({ deliveryId: messageId, sessionId: 'agent-1', state: 'started' })
    expect(service.snapshot(id).messages).toEqual(expect.arrayContaining([expect.objectContaining({ id: messageId, delivery: 'started' })]))
  })
  it('recovers a result notification saved before dispatch without rerunning work', async () => {
    await start(); await active(); service.plan(id, [task('a')]); await running('a')
    await service.finish(id, 'a', 1, 'verified result', [])
    service.stop()
    const file = join(deps.stateDir, `${id}.json`)
    const saved = JSON.parse(readFileSync(file, 'utf8'))
    saved.messages.at(-1).delivery = 'pending' // crash between durable result and dispatch
    writeFileSync(file, JSON.stringify(saved))
    sent.length = 0
    service = new OrchestratorService(deps)
    expect(tasks()[0].state).toBe('succeeded')
    service.snapshot(id)
    expect(sent).toHaveLength(1)
    expect(sent[0]).toContain('verified result')
    expect(launches).toHaveLength(2)
  })
  it('keeps assistant turns separate even when a user message arrives mid-stream', async () => {
    await start(); await active()
    service.ingest({ type: 'turn_started', agentId: 'agent-1' })
    service.ingest({ type: 'text_delta', agentId: 'agent-1', payload: { content: 'First ' } })
    service.chat(id, '33333333333333333333333333333333', 'New detail')
    service.ingest({ type: 'text_delta', agentId: 'agent-1', payload: { content: 'reply.' } })
    service.ingest({ type: 'turn_ended', agentId: 'agent-1' })
    service.ingest({ type: 'turn_started', agentId: 'agent-1' })
    service.ingest({ type: 'text_delta', agentId: 'agent-1', payload: { content: 'Second reply.' } })
    expect((service.snapshot(id).messages as Array<{ role: string; text: string }>).filter(m => m.role === 'assistant').map(m => m.text)).toEqual(['First reply.', 'Second reply.'])
  })
  it('steers the current worker once and rejects stale or finished attempts', async () => {
    await start(); await active(); service.plan(id, [task('a')]); const a = await running('a')
    const send = vi.spyOn(deps, 'send')
    const messageId = '44444444444444444444444444444444'
    service.steer(id, 'a', 1, messageId, 'Use millimeters')
    service.steer(id, 'a', 1, messageId, 'Use millimeters')
    expect(send).toHaveBeenCalledTimes(1)
    expect(send).toHaveBeenCalledWith(a.agentId, expect.stringContaining('Use millimeters'), messageId)
    expect(launches).toHaveLength(2)
    expect(() => service.steer(id, 'a', 2, messageId, 'Too late')).toThrow(/older attempt/)
    await service.finish(id, 'a', 1, 'done', [])
    expect(() => service.steer(id, 'a', 1, '55555555555555555555555555555555', 'Change it')).toThrow(/revision task/)
  })
  it('revokes only this project’s queued receipts when stopped', async () => {
    await start(); await active()
    const cancelDelivery = deps.cancelDelivery = vi.fn(() => true)
    const messageId = '66666666666666666666666666666666'
    service.chat(id, messageId, 'Queued correction')
    service.delivery({ deliveryId: messageId, sessionId: 'agent-1', state: 'queued' })
    service.cancel(id)
    expect(cancelDelivery).toHaveBeenCalledExactlyOnceWith(messageId)
    expect(service.snapshot(id).messages).toEqual(expect.arrayContaining([expect.objectContaining({ id: messageId, delivery: 'failed' })]))
  })
  it('does not race a retry against a worker still being created', async () => {
    await start(); await active()
    let resolve!: (value: { agentId: string }) => void
    deps.create = () => new Promise(r => { resolve = r })
    service.plan(id, [task('a')])
    await vi.waitFor(() => expect(resolve).toBeTypeOf('function'))
    service.cancel(id, 'a')
    expect(() => service.retry(id, 'a')).toThrow(/previous launch/)
    resolve({ agentId: 'late-worker' })
    await vi.waitFor(() => expect(cancelled).toContain('late-worker'))
    expect(tasks()[0].state).toBe('cancelled')
  })
  it('reports invalid folders as an editable request refusal', async () => {
    expect(await orchestratorRequest(service, { action: 'start', id, engine: 'claude', prompt: 'Hi', cwd: join(root, 'missing') })).toMatchObject({ error: 'INVALID_CWD' })
    expect(launches).toHaveLength(0)
  })
  it('exposes actionable wire errors without throwing or weakening validation', async () => {
    expect(await orchestratorRequest(service, { action: 'status', id: '../escape' })).toMatchObject({ error: 'INVALID_REQUEST' })
    expect(await orchestratorRequest(service, { action: 'status', id })).toMatchObject({ error: 'PROJECT_NOT_FOUND' })
    expect(await orchestratorRequest(service, { action: 'install' })).toMatchObject({ error: 'INVALID_REQUEST' })
  })
})
