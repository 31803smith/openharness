import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const io = vi.hoisted(() => ({ open: vi.fn(), configure: vi.fn() }))
vi.mock('node:fs/promises', () => ({ open: io.open }))
vi.mock('node:child_process', () => ({ execFile: io.configure }))

import { SerialLink } from './serial.js'

const again = () => Object.assign(new Error('busy'), { code: 'EAGAIN' })

describe('nonblocking serial link', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    io.configure.mockImplementation((_cmd, _args, callback) => callback(null, '', ''))
  })
  afterEach(() => { vi.useRealTimers(); vi.clearAllMocks() })

  it('preserves frame order across short writes and backpressure', async () => {
    const sent: number[] = []
    let calls = 0
    const handle = {
      read: vi.fn().mockRejectedValue(again()),
      write: vi.fn(async (bytes: Uint8Array, offset: number, length: number) => {
        if (++calls % 2 === 0) throw again()
        const count = Math.min(2, length)
        sent.push(...bytes.subarray(offset, offset + count))
        return { bytesWritten: count }
      }),
      close: vi.fn().mockResolvedValue(undefined),
    }
    io.open.mockResolvedValue(handle)
    const link = await SerialLink.open('/dev/fake', vi.fn(), vi.fn())
    const writes = Promise.all([link.write(Buffer.from([1, 2, 3, 4, 5])), link.write(Buffer.from([6, 7, 8]))])
    await vi.advanceTimersByTimeAsync(50)
    await writes
    expect(sent).toEqual([1, 2, 3, 4, 5, 6, 7, 8])
    await link.close()
  })

  it('stops retrying backpressured writes when closed and rejects queued frames', async () => {
    const handle = {
      read: vi.fn().mockRejectedValue(again()),
      write: vi.fn().mockRejectedValue(again()),
      close: vi.fn().mockResolvedValue(undefined),
    }
    io.open.mockResolvedValue(handle)
    const closed = vi.fn()
    const link = await SerialLink.open('/dev/fake', vi.fn(), closed)
    const writes = Promise.allSettled([link.write(Buffer.from('first')), link.write(Buffer.from('second'))])
    await vi.advanceTimersByTimeAsync(10)
    await Promise.all([link.close(), link.close()])
    const before = handle.write.mock.calls.length
    await vi.advanceTimersByTimeAsync(50)
    expect((await writes).map((result) => result.status)).toEqual(['rejected', 'rejected'])
    expect(handle.write).toHaveBeenCalledTimes(before)
    expect(handle.close).toHaveBeenCalledTimes(1)
    expect(closed).toHaveBeenCalledTimes(1)
  })

  it('does not deliver an old read after the link is closed', async () => {
    let finish!: (result: { bytesRead: number }) => void
    const handle = {
      read: vi.fn((buf: Buffer) => { buf[0] = 42; return new Promise((resolve) => { finish = resolve }) }),
      close: vi.fn().mockResolvedValue(undefined),
    }
    io.open.mockResolvedValue(handle)
    const received = vi.fn()
    const link = await SerialLink.open('/dev/fake', received, vi.fn())
    const closing = link.close()
    finish({ bytesRead: 1 })
    await closing
    expect(received).not.toHaveBeenCalled()
    expect(handle.read).toHaveBeenCalledTimes(1)
  })
})
