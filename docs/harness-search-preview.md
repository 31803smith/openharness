# A useful Harness search preview

The user has approved building this preview. First establish useful real content,
then implement the shared UI and cache; the earlier content-quality requirement
still applies. This document records the proposed design and its acceptance bar.

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

## The content I recommend

For an individual harness, show the latest substantive request and its latest
meaningful response or result. Put a pending question prominently when the agent
is waiting for input. Keep project, branch, machine, engine, and freshness in
compact supporting text. Avoid repeating everything already visible in the row.

For example, the useful distinction is between “app v2” as a name and an excerpt
that explains it is working on keeping only one empty New Harness tab. The actual
request and response can establish that without generating a new summary.

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

We have enough foundation to investigate this seriously. We have not established
that every selectable harness already has a complete, useful preview record.

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

## Before implementing the UI

Review actual candidate records for active, idle, waiting, tool-heavy, newly
created, unopened, and offline/remote harnesses across the major engines. Include
a group with several unrelated projects. Read the proposed request/result/question
excerpts without opening the terminal and check whether they identify the work.

If they do not, improve extraction or acknowledge the missing data first. If they
do, use those real examples to decide how much preview space is needed. Then
implement the cached-content path and verify correct identity, freshness, and
responsive selection. A good-looking empty panel is not an acceptance criterion.

Implementation is now authorized and in progress; these notes alone are not
evidence of completed UI or measured latency. See the
[Rex study](mitchellh-rex-study.md) for the related workspace and continuity lessons.
