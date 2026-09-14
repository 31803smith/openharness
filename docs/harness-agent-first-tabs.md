# Harness entry and pane controls

Users start with one harness immediately and add panes when useful. A tab holds
one or several agents without a selection basket or a separate group-creation step.
This is the latest product direction; it supersedes earlier swarm and multi-select
proposals in the progress log.

## New Harness

The tab-bar plus and Cmd-T open **New Harness**. First launch and every empty tab
use the same centered page: a **New Harness** heading, a **Find a harness…** search
field, a prominent **Create harness** button, and up to six recent harnesses below.
Search and Create sit together on desktop and stack on narrow or large-text layouts.
Recent shortcuts use existing navigation history, with open/restored sessions as
fallbacks. They are deduplicated by machine and agent, even across several tabs.

A click or Enter on a search result opens it immediately in the current tab and
reuses its runtime. A recent shortcut does the same. There is no checkbox,
selection count, Shift-Enter staging, or second confirmation step. Machine and
project groups remain searchable as a single starting-point choice. A new user
can still choose a folder first; linking, discovery, offline retry and the existing
creation recovery remain available.

**Add Agent** and split right/down use the same single-choice search and prominent
**Create Agent** button. Canceling creation returns to the original query, text
selection, highlighted row and split target. Success opens the agent directly.
The new-tab page calls its creation entry **Create harness**; the existing form
and pane operations still use agent terminology.

There is no Navigate action, compass button, or Cmd-P directory. Command search
remains on Shift-Cmd-P and stays in command mode when its query is cleared.
Typing `>` in agent search also finds commands.

## Tabs and menus

One agent shows its engine mark; multiple agents use the group mark. Returning
to one restores the engine mark. Tab names remain editable. Former default names
`New swarm`, `New tab`, and `New Agent` restore as `New Harness` and still take
the first agent's name when opened.

The macOS menus are **Harness, File, Edit, View, History, Models, Machines,
Window, Help**. File contains New Harness, Add Agent, Create Agent, split and
pane controls, Rename Tab, Close Agent Pane, Close Tab, and Add Project.
Machines lists linked computers with their status, followed by Link Machine
and Refresh Machines. Selecting a computer opens the shared search with its
name filled in; no agent is opened until the user chooses a result.

Cmd-T opens New Harness, Cmd-N opens Add Agent, Shift-Cmd-N opens Create Agent,
Cmd-W closes the tab, and Shift-Cmd-W closes the focused pane. **Cmd-1…Cmd-9**
select tabs 1…9 in their current visible order; a missing number does nothing.
**Cmd-H/J/K/L** and **Cmd-arrows** move between panes. Each tab retains its focused
pane when switching away and back. Closing views
keeps agent runtimes alive. Stored layout formats and internal command IDs remain
compatible.

## Pane chrome

The left side contains only the agent icon and session name. The right side
shows **folder • branch • machine**, omitting unavailable folder/branch data.
Long details truncate, with full context in the session-name tooltip.

Hovering anywhere on the header replaces the details with small, muted controls:
**Zoom, Delete, Close**, with **Keyboard** first for remote sessions. Keyboard
focus also reveals the controls. The title keeps the same space during the swap,
and hovering retains the terminal renderer. Delete uses the existing confirmation;
Close removes only this view. Keyboard toggles the remote message composer.

Resize grips are invisible while idle and appear on divider hover, keyboard
focus or active drag. Their hit targets and resize behavior stay the same. The
right/bottom edge plus controls continue to open Add at that split position, and
keyboard split commands remain available.
