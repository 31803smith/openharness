import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { DialLog } from './dialLog.js'

const DAY = 86_400_000

function dir() { return mkdtempSync(join(tmpdir(), 'dial-log-')) }

/** A clock the test moves by hand. */
function clock(start = Date.UTC(2026, 8, 15, 12)) {
  let t = start
  return { now: () => t, advance: (ms: number) => { t += ms } }
}

describe('DialLog', () => {
  it('writes device and daemon lines into one dated file, marked apart', async () => {
    const d = dir()
    const c = clock()
    const log = new DialLog(d, { now: c.now })
    log.daemon('open on /dev/cu.usbmodem1')
    log.device('I (1234) touch: press (200,300)')
    await log.flush()
    const text = readFileSync(log.currentPath, 'utf8')
    expect(log.currentPath).toBe(join(d, DialLog.fileName(c.now())))
    expect(text).toMatch(/^\S+ \[daemon\] open on \/dev\/cu\.usbmodem1\n\S+ I \(1234\) touch: press \(200,300\)\n$/)
  })

  it('rolls to a new file at midnight and prunes days past retention', async () => {
    const d = dir()
    const c = clock()
    // Stale files from before the window, and one just inside it.
    const stale = DialLog.fileName(c.now() - 8 * DAY)
    const kept = DialLog.fileName(c.now() - 7 * DAY) // exactly on the edge: kept today, gone tomorrow
    writeFileSync(join(d, stale), 'old\n')
    writeFileSync(join(d, kept), 'recent\n')
    writeFileSync(join(d, 'app-20260101.log'), 'not ours\n')
    const log = new DialLog(d, { now: c.now, retainDays: 7 })
    log.device('day one')
    await log.flush()
    expect(readdirSync(d).sort()).toEqual([ 'app-20260101.log', DialLog.fileName(c.now()), kept ].sort())
    c.advance(DAY)
    log.device('day two')
    await log.flush()
    const names = readdirSync(d)
    expect(names).toContain(DialLog.fileName(c.now()))
    expect(readFileSync(join(d, DialLog.fileName(c.now())), 'utf8')).toContain('day two')
    // The pruned set moves with the day: `kept` is now 8 days old and goes.
    expect(names).not.toContain(kept)
    expect(names).toContain('app-20260101.log')
  })

  it('caps a day and says so once', async () => {
    const d = dir()
    const c = clock()
    const log = new DialLog(d, { now: c.now, maxBytesPerDay: 200 })
    for (let i = 0; i < 20; i++) log.device(`line ${i} ${'x'.repeat(20)}`)
    await log.flush()
    const lines = readFileSync(log.currentPath, 'utf8').trimEnd().split('\n')
    expect(lines.at(-1)).toMatch(/\[daemon\] dial log capped for today/)
    expect(lines.filter((l) => l.includes('capped'))).toHaveLength(1)
    expect(lines.length).toBeLessThan(10)
    // A new day starts clean.
    c.advance(DAY)
    log.device('fresh')
    await log.flush()
    expect(readFileSync(log.currentPath, 'utf8')).toBe(`${new Date(c.now()).toISOString()} fresh\n`)
  })

  it('marks a missing heartbeat once, and its return', async () => {
    const d = dir()
    const c = clock()
    const log = new DialLog(d, { now: c.now, heartbeatGapMs: 90_000 })
    log.device('I (60000) ui: alive up=60s heap=100/200 lv=1 touches=3 last_press=12s')
    c.advance(60_000)
    log.tick(true)
    c.advance(31_000)
    log.tick(true)
    log.tick(true)
    await log.flush()
    let text = readFileSync(log.currentPath, 'utf8')
    expect(text.match(/no dial heartbeat for 91s/g)).toHaveLength(1)
    c.advance(30_000)
    log.device('I (180000) ui: alive up=180s heap=100/200 lv=1 touches=3 last_press=12s')
    await log.flush()
    text = readFileSync(log.currentPath, 'utf8')
    expect(text).toMatch(/dial heartbeat back after 121s/)
  })

  it('restarts the watch when the dial greets again (a reboot on an open port)', async () => {
    const d = dir()
    const c = clock()
    const log = new DialLog(d, { now: c.now, heartbeatGapMs: 90_000 })
    log.device('I (60000) ui: alive up=60s')
    c.advance(80_000)
    log.greeted()          // OTA reboot: hello arrives, ticks go back to zero
    c.advance(30_000)
    log.tick(true)         // 110s since the last beat, but only 30s since the greeting
    await log.flush()
    expect(readFileSync(log.currentPath, 'utf8')).not.toMatch(/no dial heartbeat/)
  })

  it('does not chase a heartbeat while the port is closed', async () => {
    const d = dir()
    const c = clock()
    const log = new DialLog(d, { now: c.now, heartbeatGapMs: 90_000 })
    log.device('I (60000) ui: alive up=60s')
    log.tick(false) // unplugged
    c.advance(DAY / 2)
    log.tick(true)  // back, and the first beat has not arrived yet
    await log.flush()
    const all = readdirSync(d).map((n) => readFileSync(join(d, n), 'utf8')).join('')
    expect(all).not.toMatch(/no dial heartbeat/)
  })
})
