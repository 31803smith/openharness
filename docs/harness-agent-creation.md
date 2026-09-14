# Recovering agent creation

The desktop must not interpret a lost reply as proof that no agent started.
Otherwise a second click can create a duplicate persistent session. This is
separate from the proposed Archive/Resume lifecycle; it stops no existing agent.

## Protocol

- A deliberate creation has a random `creationId`, independent of transport
  `requestId`. A retry retains it; an explicit fresh New agent action changes it.
- `agent_create` accepts an optional `creationId`. The CLI reserves it before
  calling the launcher. The same id and launch choices reuse its outcome;
  different choices return `CREATION_CONFLICT`.
- `agent_create_status` only reads the receipt. Replies echo `creationId` and
  report `missing`, `pending`, `created`, `failed`, `unconfirmed` or `unavailable`.
  `created` includes the current agent frame. `failed` carries `failure.code`
  and optional `failure.detail`, separate from RPC/transport errors.
- A missing receipt reported by a supporting CLI permits retry with the same
  id. An unsupported request, malformed reply or transport failure does not.
  Do not use a `checkOnly` flag on `agent_create`: old CLIs would launch it.
- Receipt-aware creation is detached from the connection's ordered request
  chain, so a status request can be answered while creation is still pending.
- The receipt is private machine-local state under `agent-creations`. It stores
  a hash of launch choices, the agent identity or a bounded failure, never a
  second copy of launch credentials. Reservations and replacements are fsynced;
  old receipts are not evicted and then interpreted as new requests.
- A receipt surviving a daemon interruption without a confirmed result is
  `unconfirmed`. A tmux spawn timeout or failed registration cleanup also cannot
  prove that nothing started. Those intents never launch again automatically.
  If only the completion write failed, the live daemon retains the known result.
- If an agent was subsequently deleted, replay returns `unavailable`; it does
  not create a replacement runtime.
- Both the status request and response use pairwise E2EE on relayed machines.
  The core classification hash changes only for the added frame types; the
  cryptographic format and existing frame classifications are unchanged. The
  browser/device copies in other repositories need these classifications only
  when adopting this new RPC.

## Compatibility and verification

Legacy callers without `creationId` keep the existing create response. An older
CLI can also handle a new desktop's first create, ignoring the additional field.
The desktop must check status before resending an uncertain request, including
on old CLIs where status may be unsupported or time out.

September 14 CLI checkpoint: 150 affected checks pass (receipt storage,
BackendSocket creation, existing launch helper, E2EE and relay fixtures), along
with TypeScript checking and CLI bundling. The new BackendSocket recovery tests
failed before integration. All launch callbacks use fakes and all state/sockets
are disposable. The CLI bundle was not installed or restarted.

The desktop recovery UI is the next part of this checkpoint. Real process
creation across a remote disconnect remains to be verified. A crash between
launch and receipt completion is conservatively unconfirmed, not automatically
reconciled with the runtime registry. Native benchmarking remains deferred.
