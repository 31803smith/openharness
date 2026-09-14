import { logger } from './logger.js'

/**
 * Fire-and-forget with a guaranteed catch. Node ≥ 15 turns an unhandled rejection into a process
 * crash, so a `void promise.then(async …)` whose callback awaits the DB or Redis is a latent
 * "one hiccup kills the cluster worker (and every socket on it)". Route every such call through here.
 */
export function fireAndForget(p: Promise<unknown>, what: string, ctx?: Record<string, unknown>): void {
  p.catch((err: unknown) => {
    logger.warn(`${what} failed`, { ...ctx, error: err instanceof Error ? err.message : String(err) })
  })
}
