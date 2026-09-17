/**
 * Point every test's data AND runtime dirs at throwaway directories BEFORE any module reads `env`.
 *
 * `config/env.ts` resolves `ADAPTER_DATA_DIR` at import time and defaults to the user's real
 * `~/.harness/cli/data`. Specs that import the hook server (and through it the registry) therefore wrote
 * their fixtures into the LIVE registry — a stale `late-session` record turned up there, written by
 * `launcherWs.spec.ts`, which is how this was found. Tests must never touch the user's data.
 *
 * The runtime dir is the same hazard in the other direction. It is only ever READ, but what is read
 * there — `current-grid`, `current-node` — outranks PATH by design (lib/gridExec.ts), so a real pointer
 * under `~/.harness/runtime` would send a spec's calls to this machine's managed binary instead of the
 * fake the spec put on PATH. `src/config/envIsolation.spec.ts` pins both.
 */
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

process.env.ADAPTER_DATA_DIR = mkdtempSync(join(tmpdir(), 'adapter-test-data-'))
process.env.ADAPTER_RUNTIME_DIR = mkdtempSync(join(tmpdir(), 'adapter-test-runtime-'))
