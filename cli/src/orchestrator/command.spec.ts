import { describe, expect, it } from 'vitest'
import { summarizeOrchestratorReply, parseOrchestratorArgs } from './command.js'

describe('orchestrator tool output', () => {
  it('keeps large projects readable without discarding worker results or mutating UI state', () => {
    const reply = { project: {
      id: 'a'.repeat(32), state: 'active', fingerprint: 'private-request-hash',
      tasks: [{ id: 'shape', prompt: 'long brief'.repeat(2000), summary: 'Verified', artifacts: [{ path: 'shape.step', sha256: 'a'.repeat(64) }] }],
      messages: Array.from({ length: 200 }, (_, i) => ({ id: String(i), text: 'long conversation'.repeat(1500), delivery: 'started' })),
    } }
    const output = summarizeOrchestratorReply(reply)
    expect(JSON.stringify(output).length).toBeLessThan(8000)
    expect(output).toMatchObject({ project: { tasks: [{ id: 'shape', summary: 'Verified', artifacts: [{ path: 'shape.step' }] }] } })
    expect(reply.project.messages).toHaveLength(200)
    expect(reply.project.tasks[0].prompt.length).toBeGreaterThan(10000)
  })
  it('keeps coded refusals unchanged and parses scoped steering receipts', () => {
    const error = { error: 'TASK_INACTIVE', detail: 'Add a revision task.' }
    expect(summarizeOrchestratorReply(error)).toBe(error)
    expect(parseOrchestratorArgs(['--port', '1234', '--machine', 'fixture', 'steer', 'a'.repeat(32), 'shape', '2', 'Use millimeters', 'b'.repeat(32)]).payload).toMatchObject({
      action: 'steer', taskId: 'shape', attempt: 2, text: 'Use millimeters', messageId: 'b'.repeat(32),
    })
  })
})
