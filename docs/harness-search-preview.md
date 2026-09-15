# A useful Harness search preview

Both Open Harness and inline start-page search now display existing session
content in a shared preview. This document records the content rules, data path,
and remaining coverage limits.

The start page uses a long field capped at 1120 logical pixels, with a prominent
64-pixel minimum height and **Find a harness** as its hint. Open Harness and New Harness sit underneath, aligned left,
and the device card shares that left edge over the restored lake wallpaper.
The card stays 32 pixels above the window bottom with the caption **Meet the
Harness device**. Search uses the remaining space above it. The field keeps its
position and width when search opens; results and preview appear side by
side from 700 pixels wide. The actions hide while searching. The pill buttons
retain their compact 48-pixel height below the taller field. Cmd-O retains
its existing size. Escape restores the actions and retains the query.
Page Up/Down scrolls the preview with overlap while the query keeps keyboard focus.
Arrow keys still choose results, and Enter opens the selection. The two preview
paging commands can be remapped or unbound in the Search keymap. Paging only moves
the local viewport; it never refreshes content or rebuilds the search results.

**Content rule:** never generate a summary or start a model for previews. Display
only text and metadata already available from the session.

## Implemented content path

The desktop now keeps bounded excerpts from the ordinary normalized session
stream and the existing `agent_recent` cache. A read-only audit found useful
requests and full saved responses for several existing Codex sessions; a Claude
session had neither cached text nor a meaningful transcript excerpt. Missing
content remains explicitly unavailable instead of being invented.

The cache retains up to 256 session records. Discovery warms up to 32 agents per
batch with two lightweight requests in flight, and at most 64 queued. Each
request asks for three existing entries. A one-minute freshness window coalesces
repeat reads. Agent/session replacement, removal and logout invalidate old data.
Live requests, response text and tool names update only the preview notifier;
reasoning, raw tool output and terminal buffers are not retained.

`session_get` is deliberately excluded: its response limit does not bound the
underlying transcript read. There is no full-history fallback, terminal attach,
model call, or per-keystroke request. Cached selection is synchronous; a cold
selection can schedule a lightweight read after a short dwell. First remote
content still depends on that machine responding.

## What decision should it help with?

Before opening a harness, a person should be able to answer:

- Is this the task I am looking for?
- What did this agent most recently accomplish or report?
- Does it need something from me?

Project, branch, machine, and an agent name help identify a candidate. They rarely
answer all three questions. A miniature terminal often does not answer them either.

## Why the old preview was weak

The old code at `f04f6d3` used an already-attached terminal buffer. An agent that
had not been opened locally could have no preview at all. It scanned a bounded
tail and displayed at most twelve nonblank lines, with limited width. It did not
provide a group preview, and the snapshot stayed frozen while the same result
remained highlighted.

The tail could be a prompt, progress indicator, tool output, or boilerplate.
Missing the original request made even a meaningful final line hard to interpret.
This was a content-selection and coverage problem, as well as a presentation one.
Making that same tail larger would not reliably fix it.

## Content selection

For an individual harness, show the latest substantive request and its latest
meaningful response or result. Put a pending question prominently when the agent
is waiting for input. Keep project, branch, machine, engine, and freshness in
compact supporting text. Avoid repeating everything already visible in the row.

For example, the useful distinction is between “app v2” as a name and an excerpt
that explains it is working on keeping only one empty New Harness tab. The actual
request and response can establish that without generating a new summary.

The live UI check found a common exception: the newest answer can be only a
commit receipt, while an earlier saved answer explains the feature. The preview
therefore retains the three responses already returned by `agent_recent`,
showing short, explicitly labeled earlier excerpts alongside the latest one.
Compact group previews can use the earlier explanation when the latest answer
starts with a commit/push receipt. This selects existing text without generating
a task description or claiming an earlier answer belongs to the latest request.

Selection rules matter:

- Preserve the substantive request when the most recent message is only “ok” or
  “continue.” Do not invent a task description when context is missing.
- Prefer answer text to tool spinners, repeated progress lines, and raw escape
  sequences. Preserve an actionable error rather than filtering it away.
- Associate request and answer using available turn/session identity. Do not pair
  independently collected lists merely because their indices match.
- If the current turn has no answer yet, show the request and real working state;
  do not present an older answer as the current turn's result.
- Use an existing summary only when available and attributable to the right turn.
  It should not be a prerequisite for displaying the preview.

For a group, start with one useful task/result line per member, placing waiting
agents first. A grid of tiny terminal screenshots would consume space without
making the decision easier.

## What data exists today?

| Content | Existing foundation | Remaining uncertainty |
| --- | --- | --- |
| Name, project, branch, machine, engine | Desktop Agent metadata and the cached search catalog | Incomplete metadata must remain readable. |
| Busy/idle and waiting questions | Turn events and pending-question state | Offline or old state must not appear live. |
| Actual user requests and answer text | CLI normalized session events; registered-session `session_get` reads | Need real examples across engines, session mappings, older CLIs, and cold remote sessions. |
| Recent asks and recaps | `agent_recent` and commander history | Recaps can be device-gated or absent; separately returned asks and recaps are not inherently paired. |
| Raw terminal output | Retained local terminal buffers | Useful as a fallback, but unavailable for some unopened harnesses and often noisy. |

Relevant code: [desktop search](../desktop/lib/state/swarm_search.dart),
[desktop state](../desktop/lib/state/app_state.dart),
[normalized CLI events](../cli/src/lib/normalize.ts),
[session/recent APIs](../cli/src/backendSocket.ts), and
[commander history](../cli/src/lib/commander.ts).

The read-only audit established useful content for several existing sessions,
but not every selectable harness has a complete preview record. An empty session
or older daemon can still supply no readable excerpt.

## How it can feel immediate

The [fzf preview pattern](https://github.com/junegunn/fzf#preview-window) is useful:
move through candidates, see relevant context, then accept the choice. Its preview
content comes from a command, so its speed also depends on the content provider.

For Harness, prepare small bounded excerpt records as session events arrive.
Cache them by machine, agent, and session revision. Keep those records available
before the picker opens. Arrow-key selection should only choose and render an
existing record; it should not wait for a model, a remote request, or a transcript
read. Keep terminal attachment out of the preview path.

Background refresh can improve a record without blocking navigation. Late replies
must update only their own agent/session, never replace the newly selected
candidate's preview. Keep the visible content stable while refreshing, and label
its freshness when stale or offline.

An uncached remote session still needs time to supply fresh content. Show available
context immediately and fill the missing content in asynchronously. Literal zero
latency for a cold remote fetch is not achievable; fast local selection is.

## Content audit and validation

Review actual candidate records for active, idle, waiting, tool-heavy, newly
created, unopened, and offline/remote harnesses across the major engines. Include
a group with several unrelated projects. Read the proposed request/result/question
excerpts without opening the terminal and check whether they identify the work.

If they do not, improve extraction or acknowledge the missing data first. If they
do, use those real examples to decide how much preview space is needed. Then
implement the cached-content path and verify correct identity, freshness, and
responsive selection. A good-looking empty panel is not an acceptance criterion.

The shared responsive UI and cache have been implemented. Focused checks cover
working and idle content, waiting groups, keyboard focus, session identity,
bounded fetching, offline retention and widths from 400 to 1280 logical pixels.
These are correctness checks, not native latency measurements. See the
[Rex study](mitchellh-rex-study.md) for the related workspace and continuity lessons.
