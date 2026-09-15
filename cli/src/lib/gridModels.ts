/**
 * What the account's private harness grid can answer right now.
 *
 * One `grid models --json <grid>` away, so this module is a shape and a filter rather than a
 * protocol. It exists because two things have to be decided in one place: which rows are offered to
 * a person, and what an agent is told to ask for.
 */
import { gridExec, gridJson } from './gridExec.js'
import { resolveGridMcpUrl } from './gridMcpUrl.js'

/** A row of `grid models --json`. `node` names the machine serving it — on a private grid, one of
 *  the user's own. */
interface GridModelRow {
  model?: unknown
  engine?: unknown
  node?: unknown
}

export interface GridModel {
  /** The id an engine is pointed at, verbatim from the grid. */
  id: string
  /** Which machine answers it, or empty when the grid does not say. Display only. */
  node: string
}

/**
 * The grid's router entry, which is deliberately NOT offered.
 *
 * `auto` is served by the `grid-router` engine and picks a model per request. It is being
 * reimplemented once the grid path is end-to-end encrypted, and offering it first would teach a
 * selection that is about to change meaning. Matched on the ENGINE rather than the name `auto`, so a
 * renamed router cannot leak back into the picker.
 */
const ROUTER_ENGINE = 'grid-router'

/**
 * Live models on `gridName`, router excluded. An empty list is a real answer — a grid nobody is
 * serving yet has none — and is not distinguished here from a grid that could not be reached; the
 * caller shows "no models" either way, and the reason is in the daemon log.
 */
export async function listGridModels(gridName: string | null): Promise<GridModel[]> {
  if (!gridName?.trim()) return []
  const { value } = await gridJson<GridModelRow[]>(['--remote', 'models', gridName])
  if (!Array.isArray(value)) return []

  // ⚠️ `grid models` LOWERCASES the model id; the relay does not. Measured on a real engine:
  // `grid models --json` says `qwen3.6-35b-a3b-ud-q5_k_xl` while the relay serves
  // `Qwen3.6-35B-A3B-UD-Q5_K_XL`, and posting the lowercased one answers
  // `{"detail":"No providers available for this model"}`. The id an engine is pointed at has to be
  // the one the RELAY knows, so the relay's own catalogue is the authority here and `grid models`
  // is kept only for the node label. Case is unrecoverable from the lowercased string, so this
  // cannot be fixed by mapping.
  const served = await relayModelIds(gridName)
  const nodeFor = new Map<string, string>()
  for (const row of value) {
    const id = typeof row.model === 'string' ? row.model.trim() : ''
    if (id && row.engine !== ROUTER_ENGINE) nodeFor.set(id.toLowerCase(), typeof row.node === 'string' ? row.node : '')
  }

  // The relay could not be reached (offline, no token yet) → fall back to what `grid models` said.
  // A list with the wrong case is still better than an empty picker: the engine reports the refusal
  // plainly, whereas an empty menu looks like the grid has nothing on it.
  const ids = served.length ? served : [...nodeFor.keys()]
  const seen = new Set<string>()
  const models: GridModel[] = []
  for (const id of ids) {
    const key = id.toLowerCase()
    if (!nodeFor.has(key) || seen.has(key)) continue
    seen.add(key)
    models.push({ id, node: nodeFor.get(key) ?? '' })
  }
  return models
}

/** Model ids exactly as the grid's relay serves them — the names an engine must send. Empty when the
 *  relay cannot be asked, which the caller treats as "fall back", never as "no models". */
async function relayModelIds(gridName: string): Promise<string[]> {
  const info = await gridExec(['--remote', 'info', gridName, '--env'])
  if (info.code !== 'OK') return []
  const env = readEnvExports(info.stdout)
  if (!env.baseUrl || !env.apiKey) return []
  try {
    const response = await fetch(`${env.baseUrl.replace(/\/$/, '')}/models`, {
      headers: { authorization: `Bearer ${env.apiKey}` },
      signal: AbortSignal.timeout(10_000),
    })
    if (!response.ok) return []
    const body = await response.json() as { data?: Array<{ id?: unknown }> }
    return (body.data ?? []).map((m) => (typeof m.id === 'string' ? m.id : '')).filter(Boolean)
  } catch {
    return []
  }
}


/** `grid info --env` prints shell exports; these are the two that matter. */
const ENV_LINE = /^export\s+(OPENAI_BASE_URL|OPENAI_API_KEY)=(.*)$/gm

/** What `resolveGridTarget` answers: the launch override an engine is built from. */
export interface GridTarget {
  networkId: string
  networkName: string
  baseUrl: string
  /** A live credential — see the function comment. */
  apiKey: string
  model: string
  /** The control plane's web-tools MCP endpoint. Absent when it could not be obtained; the agent
   *  then runs on the grid with no web tools, and the daemon log says why. */
  mcpUrl?: string
}

/**
 * Everything an engine needs to be pointed at `gridName`, resolved on THIS machine.
 *
 * Deliberately not something a client sends. The app names a model; the endpoint and the credential
 * are read here, from the `grid` CLI that is already signed in, so no grid credential ever crosses
 * the relay and there is one source of truth for an address the app could not know anyway.
 *
 * ⚠️ The returned `apiKey` is a live credential. It goes into the engine's ENVIRONMENT and never into
 * argv or a log line — `gridLaunch.ts` is what enforces that, and this value must keep travelling
 * through it rather than around it.
 *
 * Web tools ride on the same credential: the control plane's MCP server accepts the inference token,
 * so `mcpUrl` is the only thing added here, and it is added FIRST. `grid mcp config` renews the token
 * when it is within a month of expiry and persists the renewal; `info --env` never renews, so asked
 * in the other order it could hand inference an older token than the one the web tools hold — both
 * valid, and a mismatch nobody would think to look for. A missing `mcpUrl` degrades rather than
 * refuses: inference is the feature, web search is an accessory (`gridMcpUrl.ts`).
 */
export async function resolveGridTarget(gridName: string | null, model: string): Promise<GridTarget | null> {
  if (!gridName?.trim() || !model.trim()) return null
  const mcpUrl = await resolveGridMcpUrl(gridName)
  const info = await gridExec(['--remote', 'info', gridName, '--env'])
  if (info.code !== 'OK') return null
  const { baseUrl, apiKey } = readEnvExports(info.stdout)
  if (!baseUrl || !apiKey) return null
  // The grid's own id, for the record the launch is written into. Falls back to the name, which is
  // unique on this account and is all the launch actually needs to be re-derivable.
  const { value: rows } = await gridJson<Array<{ grid?: unknown; id?: unknown }>>(['--remote', 'ls'])
  const row = Array.isArray(rows) ? rows.find((r) => r.grid === gridName) : undefined
  return {
    networkId: typeof row?.id === 'string' ? row.id : gridName,
    networkName: gridName,
    baseUrl,
    apiKey,
    model,
    ...(mcpUrl ? { mcpUrl } : {}),
  }
}

/** The two exports out of `grid info --env`. ⚠️ Values are SHELL-QUOTED — a base URL read with the
 *  quotes still on produces a request to a host that does not exist. */
function readEnvExports(stdout: string): { baseUrl: string; apiKey: string } {
  let baseUrl = ''
  let apiKey = ''
  for (const match of stdout.matchAll(ENV_LINE)) {
    const value = match[2]!.trim().replace(/^["']|["']$/g, '')
    if (match[1] === 'OPENAI_BASE_URL') baseUrl = value
    else apiKey = value
  }
  return { baseUrl, apiKey }
}
