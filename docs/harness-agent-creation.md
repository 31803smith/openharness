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
- A missing receipt does not prove that nothing started: an older CLI may have
  launched the agent before being upgraded. Desktop status checks never resend
  creation, including for missing/unsupported receipts and transport failures.
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
The desktop keeps an uncertain request on **Check status**. On old CLIs where
status is unsupported or times out, it directs the user to **Add agent** to look
for the existing runtime. It does not guess from a title or folder match.

September 14 CLI checkpoint: 150 affected checks pass (receipt storage,
BackendSocket creation, existing launch helper, E2EE and relay fixtures), along
with TypeScript checking and CLI bundling. The new BackendSocket recovery tests
failed before integration. All launch callbacks use fakes and all state/sockets
are disposable. The CLI bundle was not installed or restarted.

## Desktop behavior

The form keeps the same creation intent and original machine, folder, engine,
profile, swarm and split. After an ambiguous reply, its choices stay visible and
locked and the primary action becomes **Check status**. Keyboard focus returns
to that action. Closing an uncertain request is labeled **Close**, not Cancel.
A confirmed refusal unlocks the choices for correction; the next deliberate
submission uses a new intent. Opening New agent also starts a fresh intent.

In a swarm, the uncertain form also offers **Find a harness**. It closes
the form and opens the shared Add picker, with its input focused and the query
retained when creation began from search. This only searches the catalog; it
does not infer the created agent from a matching name/folder or start another.
The picker targets the original swarm and split, returning to that swarm if
the active tab changed. A closed swarm or stale split shows an explanation
and asks the user to choose a destination again. The modal handoff waits for
the route to return keyboard ownership. An empty tab appearing behind the
dialog cannot take that focus for its welcome search.

When creation starts from centered Add or a split, clicking outside or pressing
**Escape** dismisses the entire flow and restores the original terminal's keyboard
input. **Back to Search** explicitly returns to the picker with its query, text
selection, highlighted result and split target intact. Direct creation retains
**Cancel**. **Find a harness** on an uncertain request also restores that search
draft. Successful creation keeps the picker closed. Returning to search never
silently redirects a stale split; a changed target gets an explanation.

New Tab (Cmd-T) creates a temporary workspace with the shared picker. Cancelling
creation also discards that unused workspace and returns to the previous harness;
success commits it. With no other populated workspace, cancellation restores the
starting picker. Cmd-N opens creation directly; Cmd-O opens harness search. A
changed or closed destination never redirects a successful creation into another
workspace, and returning to an empty replacement always restores its picker.

The restored draft reads the current catalog and validates its target and
capacity again. There is no multi-select or checked-agent draft. The draft exists
only for this temporary detour; it does not persist a pending creation receipt or
survive an app restart.

Recovery opens the returned agent in the original swarm/position and counts the
creation once. If that destination changed or closed, the runtime remains in
the catalog for Add agent without opening a different tab or deleting anything.
Concurrent submits for the same intent share one pending request. Late engine,
profile and folder results cannot change the original launch choices.

The receipt is durable on the CLI; the desktop form's intent is in memory. Closing
the form or restarting the app currently ends that form's recovery path. A future
pending-creations list could retain it across those boundaries. Do not describe
this as automatic recovery across a desktop restart or an Archive/Resume feature.

Desktop validation: 127 affected checks pass, including 15 creation-recovery
regressions and the team's concurrent Option-Enter input tests. A separate
real-font render check passes at 880×560 with normal and 2× text. Static analysis
has no errors/warnings and the same 14 existing infos. The normal arm64 Release
build succeeds at
`/private/tmp/harness-creation-release/Build/Products/Release/Harness.app` with
the production `lib/main.dart` entry point. It was not launched. Logs:
`/private/tmp/harness-creation-{desktop-tests,final-recovery,analyze,release}.log`.
The fixtures never create, stop or send input to a real agent.

Real process creation across a remote disconnect remains to be verified. A crash
between launch and receipt completion is conservatively unconfirmed, not
automatically reconciled with the runtime registry. Native benchmarking remains
deferred.

The subsequent Find existing continuation passes 87 affected creation,
onboarding, Add, split and keyboard checks, plus a real-font render check with
normal and 2× text. Six new regressions cover centered Add, the New swarm
search shortcut, switched/closed swarms and valid/stale splits. All use fake
creation replies and record that recovery sends no second launch or terminal
input. Analysis still has zero errors/warnings and the same 14 existing infos.
Logs: `/private/tmp/harness-find-created-{workflows,final-recovery,analyze}.log`.
The normal arm64 Release build also passes with the production entry point at
`/private/tmp/harness-find-created-release/Build/Products/Release/Harness.app`;
log: `/private/tmp/harness-find-created-release.log`. The app was not launched
and the user's running app and agents were not restarted.

The subsequent Add-return continuation passes 76 affected workflow checks and
one real-font render check at minimum window size and normal/2× text. Nine new
checks cover cancellation, successful/uncertain creation, stale destinations
and selection revalidation. Three reproduced the original loss of the picker;
the split input check also confirms the next key reaches the original terminal
after Add is dismissed. Analysis has no errors/warnings and 14 existing infos.
Logs: `/private/tmp/harness-add-return-final-{tests,analyze}.log`. These use
synthetic agents/replies, including the production Dart keyboard dispatcher;
native Shift-Enter still needs direct verification. Inline New swarm retains
its text but still drops optional checked selections on focus loss.
The normal arm64 Release build succeeds at
`/private/tmp/harness-add-return-release/Build/Products/Release/Harness.app`;
log: `/private/tmp/harness-add-return-release.log`. It was not launched.
