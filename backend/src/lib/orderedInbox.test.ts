import { describe, expect, it, vi } from 'vitest'
import { createOrderedInbox } from './orderedInbox.js'

const tick = (): Promise<void> => new Promise((r) => setImmediate(r))

describe('createOrderedInbox', () => {
  it('processes frames strictly in order even when a handler is slow', async () => {
    const seen: number[] = []
    let releaseFirst!: () => void
    const inbox = createOrderedInbox<number>(
      async (n) => {
        if (n === 1) await new Promise<void>((r) => { releaseFirst = r })
        seen.push(n)
      },
      () => { throw new Error('unexpected') },
      () => { throw new Error('unexpected overflow') },
    )
    inbox.enqueue(1); inbox.enqueue(2); inbox.enqueue(3)
    await tick()
    expect(seen).toEqual([])
    expect(inbox.inflight()).toBe(3)
    releaseFirst()
    await tick(); await tick(); await tick()
    expect(seen).toEqual([1, 2, 3])
    expect(inbox.inflight()).toBe(0)
  })

  it('refuses frames past maxInflight, reports them, and keeps the chain intact', async () => {
    const overflow = vi.fn()
    let release!: () => void
    const handled: number[] = []
    const inbox = createOrderedInbox<number>(
      async (n) => { if (n === 1) await new Promise<void>((r) => { release = r }); handled.push(n) },
      () => undefined,
      overflow,
      { maxInflight: 2 },
    )
    expect(inbox.enqueue(1)).toBe(true)
    expect(inbox.enqueue(2)).toBe(true)
    expect(inbox.enqueue(3)).toBe(false)
    expect(overflow).toHaveBeenCalledWith(3, 2)
    expect(inbox.inflight()).toBe(2)
    await tick() // the first handler has started and parked on `release`
    release()
    await tick(); await tick(); await tick()
    expect(handled).toEqual([1, 2])
    // capacity is back once the chain drained
    expect(inbox.enqueue(4)).toBe(true)
    await tick(); await tick()
    expect(handled).toEqual([1, 2, 4])
  })

  it('routes a throwing handler to onError and continues with the next frame', async () => {
    const onError = vi.fn()
    const handled: number[] = []
    const inbox = createOrderedInbox<number>(
      async (n) => { if (n === 1) throw new Error('boom'); handled.push(n) },
      onError,
      () => undefined,
    )
    inbox.enqueue(1); inbox.enqueue(2)
    await tick(); await tick(); await tick()
    expect(onError).toHaveBeenCalledTimes(1)
    expect((onError.mock.calls[0][0] as Error).message).toBe('boom')
    expect(handled).toEqual([2])
    expect(inbox.inflight()).toBe(0)
  })
})
