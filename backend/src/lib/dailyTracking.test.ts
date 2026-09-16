import { beforeEach, describe, expect, it, vi } from 'vitest'

const db = vi.hoisted(() => ({
  machinePresenceUpsert: vi.fn(),
}))

vi.mock('./prisma.js', () => ({
  prisma: {
    machineDailyPresence: { upsert: db.machinePresenceUpsert },
  },
}))

import { presenceWriteDue, touchMachineOnlineDay } from './dailyTracking.js'
import { utcDayStart } from '../types/analytics.js'

describe('touchMachineOnlineDay', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    db.machinePresenceUpsert.mockResolvedValue({})
  })

  it('upserts the (machine, UTC day) row and bumps connections on a new connection', async () => {
    const now = new Date('2026-09-16T10:15:30.000Z')
    await touchMachineOnlineDay('user-1', 'machine-a', now, { isNewConnection: true })

    expect(db.machinePresenceUpsert).toHaveBeenCalledTimes(1)
    const call = db.machinePresenceUpsert.mock.calls[0][0]
    expect(call.where).toEqual({ machineId_dayUtc: { machineId: 'machine-a', dayUtc: utcDayStart(now) } })
    expect(call.create).toEqual({
      machineId: 'machine-a', userId: 'user-1', dayUtc: utcDayStart(now),
      connections: 1, firstSeenAt: now, lastSeenAt: now,
    })
    expect(call.update).toEqual({ lastSeenAt: now, connections: { increment: 1 } })
  })

  it('only touches lastSeenAt on a heartbeat/close (no connections increment)', async () => {
    const now = new Date('2026-09-16T23:59:59.000Z')
    await touchMachineOnlineDay('user-1', 'machine-a', now, { isNewConnection: false })

    const call = db.machinePresenceUpsert.mock.calls[0][0]
    expect(call.update).toEqual({ lastSeenAt: now })
    // First write of a new UTC day from a session that spans midnight: the row exists, but no
    // connection was opened on that day.
    expect(call.create.connections).toBe(0)
  })

  it('propagates a DB failure so the caller can log it and keep its guard unchanged', async () => {
    db.machinePresenceUpsert.mockRejectedValueOnce(new Error('mongo down'))
    await expect(
      touchMachineOnlineDay('user-1', 'machine-a', new Date(), { isNewConnection: true }),
    ).rejects.toThrow('mongo down')
  })
})

describe('presenceWriteDue', () => {
  const FIVE_MIN = 5 * 60_000
  const t0 = new Date('2026-09-16T10:00:00.000Z')

  it('is due before anything has been written', () => {
    expect(presenceWriteDue({ dayKey: null, wroteAt: 0 }, t0, FIVE_MIN)).toBe(true)
  })

  it('is not due within the interval on the same UTC day', () => {
    const last = { dayKey: '2026-09-16', wroteAt: t0.getTime() }
    expect(presenceWriteDue(last, new Date(t0.getTime() + 15_000), FIVE_MIN)).toBe(false)
    expect(presenceWriteDue(last, new Date(t0.getTime() + FIVE_MIN - 1), FIVE_MIN)).toBe(false)
  })

  it('is due once the interval has elapsed', () => {
    const last = { dayKey: '2026-09-16', wroteAt: t0.getTime() }
    expect(presenceWriteDue(last, new Date(t0.getTime() + FIVE_MIN), FIVE_MIN)).toBe(true)
  })

  it('is due when the UTC day rolled over, even inside the interval', () => {
    const lateNight = new Date('2026-09-16T23:59:50.000Z')
    const last = { dayKey: '2026-09-16', wroteAt: lateNight.getTime() }
    expect(presenceWriteDue(last, new Date('2026-09-17T00:00:05.000Z'), FIVE_MIN)).toBe(true)
  })
})
