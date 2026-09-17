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
process.env.DSH_DIR = join(process.env.ADAPTER_DATA_DIR, 'dsh')
// The Store catalog is fetched from GitHub by dsh_list; a test must never depend on what that branch
// holds today (a published catalog turned a fixture registry of two into the live shelf of 23).
// Loopback port 9 refuses at once, so the live catalog falls back to the registry each test stubs.
process.env.HARNESS_STORE_CATALOG_URL ??= 'http://127.0.0.1:9/catalog.json'
