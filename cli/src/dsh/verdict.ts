/**
 * `.harness/verdict.json` — the one file a DSH's own scripts write and Harness reads back.
 *
 * Spec 1 (`dsh/spec/schema/verdict.schema.json`): `ready` is the one machine fact, `findings` carry
 * a closed severity and an open kind, `artifact` names the primary thing to view. The daemon reduces
 * it to what the pane header needs (ready, a summary, two counts) and hands `artifact` to the viewer.
 *
 * Watched per agent through the `.harness` directory rather than the file, because a writer that
 * truncates-then-writes, or renames into place, looks different to the two watch strategies and the
 * directory sees both.
 */
import chokidar, { type FSWatcher } from 'chokidar'
import { existsSync, mkdirSync, readFileSync } from 'node:fs'
import { basename, dirname } from 'node:path'

export interface DshVerdict {
  ready: boolean
  summary: string | null
  errors: number
  warnings: number
  artifact: string | null
  updatedAt: string | null
}

function cleanRelative(value: unknown): string | null {
  if (typeof value !== 'string' || !value || value.length > 1024) return null
  if (value.startsWith('/') || value.split(/[\\/]/).some((segment) => segment === '..')) return null
  return value
}

/** Reduce a verdict file to the wire shape; null when it is not a spec-1 verdict. */
export function parseVerdict(text: string): DshVerdict | null {
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    return null
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const raw = value as Record<string, unknown>
  if (raw.spec !== 1 || typeof raw.ready !== 'boolean') return null
  let errors = 0
  let warnings = 0
  if (Array.isArray(raw.findings)) {
    for (const finding of raw.findings) {
      const severity = (finding as { severity?: unknown } | null)?.severity
      if (severity === 'error') errors++
      else if (severity === 'warning') warnings++
    }
  }
  const summary = typeof raw.summary === 'string' && raw.summary.trim()
    ? raw.summary.trim().slice(0, 200)
    : null
  const updatedAt = typeof raw.updatedAt === 'string' && !Number.isNaN(Date.parse(raw.updatedAt))
    ? raw.updatedAt
    : null
  return { ready: raw.ready, summary, errors, warnings, artifact: cleanRelative(raw.artifact), updatedAt }
}

export function readVerdictFile(file: string): DshVerdict | null {
  try {
    return parseVerdict(readFileSync(file, 'utf8'))
  } catch {
    return null
  }
}

const DEBOUNCE_MS = 150

interface Watched {
  file: string
  watcher: FSWatcher
  timer: NodeJS.Timeout | null
  last: string | null
}

export interface DshVerdictWatcherDeps {
  /** The verdict changed (or went away → null). */
  onChange: (agentId: string, verdict: DshVerdict | null) => void
  log?: (line: string) => void
}

export class DshVerdictWatcher {
  private readonly watched = new Map<string, Watched>()

  constructor(private readonly deps: DshVerdictWatcherDeps) {}

  /** Idempotent: watching the same file again is a no-op; a different file replaces the watch. */
  watch(agentId: string, file: string): void {
    const current = this.watched.get(agentId)
    if (current?.file === file) return
    if (current) this.unwatch(agentId)
    const dir = dirname(file)
    try {
      mkdirSync(dir, { recursive: true })
    } catch (error) {
      this.deps.log?.(`[dsh] verdict dir ${dir} could not be created · ${error instanceof Error ? error.message : error}`)
      return
    }
    const name = basename(file)
    const watcher = chokidar.watch(dir, { ignoreInitial: true, depth: 0, persistent: true })
    const entry: Watched = { file, watcher, timer: null, last: null }
    const schedule = (): void => {
      if (entry.timer) clearTimeout(entry.timer)
      entry.timer = setTimeout(() => {
        entry.timer = null
        this.publish(agentId, entry)
      }, DEBOUNCE_MS)
      entry.timer.unref?.()
    }
    const relevant = (path: string): boolean => basename(path) === name
    watcher
      .on('add', (path: string) => { if (relevant(path)) schedule() })
      .on('change', (path: string) => { if (relevant(path)) schedule() })
      .on('unlink', (path: string) => { if (relevant(path)) schedule() })
      .on('error', (error: unknown) => this.deps.log?.(`[dsh] verdict watch error · ${error instanceof Error ? error.message : error}`))
    this.watched.set(agentId, entry)
    // What is already there counts: a restored agent's last verdict is still its verdict.
    if (existsSync(file)) this.publish(agentId, entry)
  }

  private publish(agentId: string, entry: Watched): void {
    let text: string | null
    try {
      text = readFileSync(entry.file, 'utf8')
    } catch {
      text = null
    }
    if (text === entry.last) return
    entry.last = text
    this.deps.onChange(agentId, text === null ? null : parseVerdict(text))
  }

  current(agentId: string): DshVerdict | null {
    const entry = this.watched.get(agentId)
    return entry?.last ? parseVerdict(entry.last) : null
  }

  unwatch(agentId: string): void {
    const entry = this.watched.get(agentId)
    if (!entry) return
    this.watched.delete(agentId)
    if (entry.timer) clearTimeout(entry.timer)
    void entry.watcher.close()
  }

  async stop(): Promise<void> {
    const entries = [...this.watched.values()]
    this.watched.clear()
    await Promise.all(entries.map((entry) => {
      if (entry.timer) clearTimeout(entry.timer)
      return entry.watcher.close()
    }))
  }
}
