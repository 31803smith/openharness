# Agent lifecycle: stop accumulating live sessions

Proposal, September 14, 2026. The user raised this problem while reviewing the
current developer experience. This document is a design recommendation, not an
implemented lifecycle or authorization to stop existing agents.

The user values closing a pane without ending its agent, but repeatedly creating
agents leaves an ever-growing collection of running sessions. Preserve that
useful separation and add an explicit way to finish work for now.

## Recommended experience

| Action | Meaning |
| --- | --- |
| Remove from swarm | Remove this view only. The agent and its other swarm memberships keep working. This is the existing view action, now labeled consistently in the pane menu, native menu and keyboard help. |
| Archive agent | Stop its runtime, preserve its conversation reference and launch context, and move it out of the active collection. This affects the agent across swarms, not only one pane. |
| Resume | Restore the archived conversation in a runtime and add it to the chosen swarm. Reuse the same Harness agent identity. |
| Delete agent | Keep the separate explicit removal action. Do not treat ordinary closure or archiving as permission to delete project files or provider transcripts. |

- Put Archive agent in the pane menu and the Agent menu. Explain that it stops
  the agent and saves it for later. Closing a swarm continues to close views.
- Add and machine/project starters show active agents by default. Archived
  agents remain discoverable through History and an explicit Archived filter;
  their action says Resume and add. Navigate continues to describe existing
  open destinations, with no implicit restart or membership changes.
- Offer Archive unused agents… as an explicit bulk cleanup action. List
  candidates with machine/project, last activity and known swarm membership.
  Let the user choose and review the set. Do not turn local absence from a swarm
  into an automatic stop rule: an agent may still be useful elsewhere.
- Keep Cmd-N opening Add so reusing existing work remains the primary entry.
  New agent still means a fresh agent. Do not silently redirect a deliberate
  creation into an older conversation.
- Start with deliberate archive/resume and bulk cleanup. Automatic inactivity
  policies can come later. Quiet terminal output does not establish that an
  agent has finished working.

## Existing view recovery

The September 14 continuation clarifies the existing removal action and fixes
partial History recovery. If someone reopens an individual agent before its
original swarm, reopening that swarm restores only its missing views into the
same tab. It preserves the current name, focus, presets, pins and shared live
sessions rather than creating another same-named swarm. Recovery checks available
pane capacity before making any change and keeps the history entry if it cannot
fit. This does not archive, stop, or restart agent runtimes; Archive/Resume above
remains a proposal.

## What implementation must preserve

Archive must be durable on the agent's machine, shared with other clients and
honored by discovery/reboot restoration. Hiding a row in the desktop alone would
leave the process running and recreate the same accumulation problem.

Store and validate the existing provider session identifier, working directory,
profile/launch references and useful recent output before stopping. Confirm
termination before reporting Archived. If saving or stopping fails, retain a
visible recoverable agent and report the actual outcome. Do not expose launch
credentials in UI or copy them into desktop preferences.

Resume is conversation restoration, not an exact snapshot of process memory.
Only offer the promised stop-and-resume path where the provider/session can
support it. Explain unsupported cases before any stop. If resuming fails, keep
the archived record with Retry; starting a fresh conversation must be a separate
explicit action. An active task needs an explicit interruption decision, and
bulk selection should not include working agents by default.

Current source has useful pieces but not this contract:

- `cli/src/cli.ts` handles `agent_delete` by forgetting the live registration
  and asynchronously terminating the validated engine process. It preserves
  some recap/name data; it is not an acknowledged Archive operation.
- `cli/src/lib/restartAgent.ts` tries the provider session and may fall back to
  a fresh conversation. That fallback must not be reused silently for Resume.
- `cli/src/lib/restoreAgents.ts` recreates missing registered runtimes after a
  reboot. An archived state must explicitly exclude those entries from this
  restoration and from discovery that would otherwise resurrect them.

Acceptance checks should cover repeated requests, offline and partial failures,
agent identity across clients, daemon restarts, shared swarm memberships,
unsupported resume, and preservation of provider/workspace choices. Exercise
process termination only with disposable fixtures; current user agents are not
test inputs or cleanup targets.

## Reference

VS Code documents archiving completed agent sessions, restoring them to the
active list, and filtering archived sessions separately. That supports the
organizational pattern; it does not establish Harness's proposed process-stop
or provider-resume guarantees. [Manage agent sessions](https://code.visualstudio.com/docs/agents/run/sessions/manage-sessions#archive-sessions).
