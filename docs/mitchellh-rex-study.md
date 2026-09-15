# Rex: what Harness can learn

Discussion notes from the three Mitchell Hashimoto posts requested by the user.
The posts, demo visuals, and full captions for the two narrated demos were
reviewed. These are observations and proposals, not implemented Harness features.

## The three demonstrations

| Post | What it demonstrates | My takeaway for Harness |
| --- | --- | --- |
| [CLI automation](https://x.com/mitchellh/status/2099622049325232505) | The CLI creates named sessions, launches processes, changes layout, observes events, waits for process exit, and captures or sends terminal content. | A person and an agent should operate on the same workspace objects. Automation becomes more useful when its work is visible and navigable. |
| [Appearance](https://x.com/mitchellh/status/2097449191325028407) | Coordinated themes, interface treatments, and comfortable/compact pane density. Mitchell also shows his Petrol Lagoon setup. | Delight comes from a coherent whole: contrast, spacing, hierarchy, and surfaces that belong together. |
| [Remote sessions](https://x.com/mitchellh/status/2097424868203758046) | Persistent remote sessions, local CLI access to remote work, and familiar directory navigation on either machine. | Remote work should preserve your place and habits while keeping machine identity clear. |

### 1. One workspace for people and automation

In the CLI demo, a command launches a named session with a process that immediately
appears in the GUI. A running editor can move between split arrangements without
restarting. Other commands enumerate workspace objects, wait for exit status,
observe events, and capture terminal content. Those are useful composable
operations, rather than automation that depends on screen coordinates.

For Harness, a promising application would be an agent preparing a workspace with
its task, tests, and logs, then leaving that arrangement for a person to inspect.
Events could identify where attention is needed without repeatedly polling every
pane. Stable identity would let the UI, device, and automation refer to the same
work after a tab moves or reconnects.

This is an architectural lesson, not a proposal to reproduce the entire CLI.
Also, a child process exiting is not proof that an AI task is complete; Harness
needs to distinguish process lifecycle from meaningful agent progress.

### 2. Coherence and density

The [quoted appearance demonstration](https://x.com/almonk/status/2097439320076403125)
shows themes and interface choices changing the surrounding app as well as the
terminal. Comfortable spacing gives panes more separation; compact spacing leaves
more room for content. The settings show actual visual previews of the choices.

My recommendation is to start with a few excellent coordinated defaults. A larger
collection of themes would not solve weak hierarchy or crowded controls. Two
thoughtful density settings could eventually serve different workflows: generous
spacing for a few agents, compact spacing when many panes need to stay visible.

The relevant lesson for the New Harness form is room to read and choose: clear
sections, stable selection states, and optional details revealed when needed.
Rounded buttons alone do not make the creation flow easier.

### 3. Continuity across machines

The remote demo shows sessions surviving the GUI closing and reopening. The same
directory-navigation flow works remotely, including a Go To Directory action,
path suggestions, and opening a terminal in the chosen location. CLI-created
remote work appears in the GUI too.

For Harness, the priority should be continuity of task, output position, focus,
draft, and layout. Switching machines should not require learning another way
to browse or open work. Machine identity still matters and should remain visible.

The demo does not establish measured Harness latency, nor does it imply we should
replace our transport. Familiar interaction and retained local state are lessons
we can apply independently of the network implementation.

## How I would prioritize the lessons

1. Make the next action obvious: creating work, finding existing work, and knowing
   which agent will receive input.
2. Give search enough context to recognize the right task before opening it.
3. Preserve that context and input ownership through navigation and reconnects.
4. Keep spacing, icons, labels, and surfaces consistent across the application.
5. Explore agent-driven workspace automation after those everyday flows are solid.

The separate [search preview proposal](harness-search-preview.md) examines the
content we have, why the previous preview was weak, and how a useful preview could
feel immediate. The larger New Harness creation-form redesign is still pending;
none of these demos should be treated as approval to implement new features.
