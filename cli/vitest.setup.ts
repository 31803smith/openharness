/**
 * Point every test's data dir at a throwaway directory BEFORE any module reads `env`.
 *
 * `config/env.ts` resolves `ADAPTER_DATA_DIR` at import time and defaults to the user's real
 * `~/.harness/cli/data`. Specs that import the hook server (and through it the registry) therefore wrote
 * their fixtures into the LIVE registry — a stale `late-session` record turned up there, written by
 * `launcherWs.spec.ts`, which is how this was found. Tests must never touch the user's data.
 */
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

process.env.ADAPTER_DATA_DIR = mkdtempSync(join(tmpdir(), 'adapter-test-data-'))
process.env.DSH_DIR = join(process.env.ADAPTER_DATA_DIR, 'dsh')
// The Store catalog is fetched from GitHub by dsh_list; a test must never depend on what that branch
// holds today (a published catalog turned a fixture registry of two into the live shelf of 23).
// Loopback port 9 refuses at once, so the live catalog falls back to the registry each test stubs.
process.env.HARNESS_STORE_CATALOG_URL ??= 'http://127.0.0.1:9/catalog.json'
