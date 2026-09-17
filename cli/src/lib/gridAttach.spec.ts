import { describe, expect, it, vi } from 'vitest'
import { reconcileGridAttach, type GridAttachDeps } from './gridAttach.js'
import type { GridHandoffResult } from './gridHandoff.js'
import type { EnsureResult } from './gridEnsure.js'

const NAME = 'someone-7f3a91c4'
const EMAIL = 'someone@autonomous.ai'

const OK_HANDOFF: GridHandoffResult = { code: 'OK', exitCode: 0, message: '', stdout: '', stderr: '' }
const MISSING_HANDOFF: GridHandoffResult = {
  code: 'GRID_CLI_MISSING', exitCode: 1, message: 'no grid', stdout: '', stderr: '',
}
const EXISTED: EnsureResult = { status: 'existed', message: '' }
const CREATED: EnsureResult = { status: 'created', message: '' }

/** Deps with every seam a no-op success, so a test overrides only the one it is about. */
function deps(over: Partial<GridAttachDeps> = {}): GridAttachDeps & {
  handoff: ReturnType<typeof vi.fn>
  ensure: ReturnType<typeof vi.fn>
  onName: ReturnType<typeof vi.fn>
} {
  const base = {
    managedGridReady: Promise.resolve(),
    gridAvailable: () => true,
    mintName: async () => NAME,
    accessToken: async () => 'tok',
    signedInEmail: () => EMAIL,
    gridNames: async () => [NAME],
    handoff: vi.fn(async () => OK_HANDOFF),
    ensure: vi.fn(async () => EXISTED),
    onName: vi.fn(),
    log: () => {},
  }
  return { ...base, ...over } as never
}

describe('reconcileGridAttach — the daemon-start convergence', () => {
  it('does nothing but publish the name when already signed in as the right account with the grid present', async () => {
    const d = deps()
    const r = await reconcileGridAttach(d)

    expect(r.status).toBe('converged')
    expect(r.name).toBe(NAME)
    expect(d.handoff).not.toHaveBeenCalled()
    expect(d.ensure).not.toHaveBeenCalled()
    expect(d.onName).toHaveBeenCalledWith(NAME)
  })

  it('re-signs in and ensures when the account name is not known locally (never created, or not synced here)', async () => {
    // The name is not in the local `grid ls`, so the machine cannot be proven to be set up — it
    // (re)signs in as this account and ensures the grid rather than acting on a weaker guess.
    const d = deps({ gridNames: async () => [], ensure: vi.fn(async () => CREATED) })
    const r = await reconcileGridAttach(d)

    expect(r.status).toBe('signed-in')
    expect(d.handoff).toHaveBeenCalledWith('tok')
    expect(d.ensure).toHaveBeenCalledWith(NAME)
    expect(d.onName).toHaveBeenCalledWith(NAME)
  })

  it('does not false-positive across two accounts sharing an email local-part', async () => {
    // Signed in to grid as `someone@personal` (grid `someone-11112222`) while the harness account is
    // `someone@company` (minted `someone-7f3a91c4`). The names differ, so the local `grid ls` does
    // NOT contain the harness account's name — this must overwrite, not skip.
    const d = deps({ signedInEmail: () => 'someone@personal.example', gridNames: async () => ['someone-11112222'] })
    const r = await reconcileGridAttach(d)

    expect(r.status).toBe('signed-in')
    expect(d.handoff).toHaveBeenCalledOnce()
    expect(d.ensure).toHaveBeenCalledWith(NAME)
  })

  it('hands the token over, then ensures, when this machine has no grid sign-in', async () => {
    const d = deps({ signedInEmail: () => null, gridNames: async () => [] })
    const r = await reconcileGridAttach(d)

    expect(r.status).toBe('signed-in')
    expect(d.handoff).toHaveBeenCalledWith('tok')
    expect(d.ensure).toHaveBeenCalledWith(NAME)
    expect(d.onName).toHaveBeenCalledWith(NAME)
  })

  it('overwrites a different account: signed in as someone else means a hand-off', async () => {
    // The signed-in email's pattern does not match the account's minted name.
    const d = deps({ signedInEmail: () => 'other@elsewhere.io', gridNames: async () => ['other-11112222'] })
    const r = await reconcileGridAttach(d)

    expect(r.status).toBe('signed-in')
    expect(d.handoff).toHaveBeenCalledOnce()
    expect(d.ensure).toHaveBeenCalledWith(NAME)
  })

  it('does nothing and reports no-cli when there is no grid binary', async () => {
    const d = deps({ gridAvailable: () => false, mintName: vi.fn() as never })
    const r = await reconcileGridAttach(d)

    expect(r.status).toBe('no-cli')
    expect(d.onName).not.toHaveBeenCalled()
    expect((d.mintName as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled()
  })

  it('stops at no-name on an older backend that mints none, without touching grid', async () => {
    const d = deps({ mintName: async () => null })
    const r = await reconcileGridAttach(d)

    expect(r.status).toBe('no-name')
    expect(d.handoff).not.toHaveBeenCalled()
    expect(d.ensure).not.toHaveBeenCalled()
    expect(d.onName).not.toHaveBeenCalled()
  })

  it('stops at no-name when the control plane is unreachable — and will try again next start', async () => {
    const d = deps({ mintName: async () => { throw new Error('ECONNREFUSED') } })
    const r = await reconcileGridAttach(d)

    expect(r.status).toBe('no-name')
    expect(r.detail).toContain('ECONNREFUSED')
    expect(d.handoff).not.toHaveBeenCalled()
  })

  it('reports handoff-failed without ensuring, leaving the harness sign-in untouched', async () => {
    const d = deps({ signedInEmail: () => null, handoff: vi.fn(async () => MISSING_HANDOFF) })
    const r = await reconcileGridAttach(d)

    expect(r.status).toBe('handoff-failed')
    expect(d.ensure).not.toHaveBeenCalled()
    expect(d.onName).not.toHaveBeenCalled()
  })

  it('waits for the managed grid runtime before checking the binary', async () => {
    const order: string[] = []
    let releaseRuntime = (): void => {}
    const runtime = new Promise<void>((res) => { releaseRuntime = () => { order.push('runtime'); res() } })
    const d = deps({
      managedGridReady: runtime,
      gridAvailable: () => { order.push('available'); return false },
    })

    const done = reconcileGridAttach(d)
    // The binary check must not have run before the runtime promise settled.
    await Promise.resolve()
    expect(order).toEqual([])
    releaseRuntime()
    await done
    expect(order).toEqual(['runtime', 'available'])
  })

  it('does not let a rejected runtime promise throw — a failed download is best-effort', async () => {
    const d = deps({ managedGridReady: Promise.reject(new Error('download failed')), gridAvailable: () => false })
    await expect(reconcileGridAttach(d)).resolves.toMatchObject({ status: 'no-cli' })
  })
})
