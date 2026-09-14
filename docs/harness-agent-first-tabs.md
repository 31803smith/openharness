# Harness entry and pane controls

Users start with one harness immediately and add panes when useful. A tab holds
one or several harnesses without a selection basket or a separate group-creation step.
This is the latest product direction; it supersedes earlier swarm and multi-select
proposals in the progress log.

## New Harness

The tab-bar plus and **Cmd-T / New Tab** open a draft workspace and immediately
show the same centered picker as **Cmd-O / Find Harness** and floating +. First launch, reopening an
empty workspace, and closing its last pane use this entry point too. There is no
separate start page, inline search, or recent-work list to maintain.

The picker has a full-width **Find a harness** field and single-choice results.
A click or Enter opens one result immediately in the destination, reusing its
runtime. Machine and project groups remain searchable as starting points. There
is no checkbox, selection count, or separate group-creation step. Closing the
picker discards an unused draft and returns to the previous harness. Drafts are
not persisted or added to History. Selecting an existing harness or successfully
creating one commits the draft. Repeated New Tab while the starter is empty reuses
it. If no populated workspace exists, dismissal keeps the picker ready; the app
never strands the user on a blank page. Named empty layouts are preserved.

Results show a prominent session name and secondary **project · branch · machine**
metadata, omitting missing fields. The containing workspace name remains searchable
but is omitted from the subtitle. Only the highlighted row shows **Open Harness**,
**Add Harness**, or **Split right/down**, according to the destination. There is no
Commands footer or repeated action. Unavailable results still explain why they
cannot open. Command search remains available through Shift-Cmd-P and by typing
`>` in ordinary search; the shortcuts guide documents it.

A short **or** divider and accented **+ New Harness** button sit outside and
below the card. The divider spans 160 logical pixels, with 32 pixels of breathing
room above and below. Popups use a 90% black overlay. The button starts fresh
creation in the picker’s destination, including its split position. First-use
folder selection, discovery, linking, reconnect and creation recovery remain
available through this shared entry point.

Clicking outside creation or pressing Escape dismisses the entire flow and
restores terminal keyboard focus. **Back to Search** deliberately restores its
query, text selection, highlighted row and split target. Direct creation retains
**Cancel**; an uncertain request retains **Close** and explicit search recovery.
A new empty workspace appearing behind a dialog cannot reopen search over it.
Success opens the harness directly.

**Harness** names the work users open, create, rename, and close. **Agent** names
the engine inside it: Codex, Claude Code, Cursor, or another coding agent. The
creation dialog is **Create Harness**, with the same CTA on every machine;
**Clone repository** has no trailing ellipsis. Internal agent IDs, RPCs and stored
session/layout schemas remain compatible.

There is no Navigate action, compass button, or Cmd-P directory. Command search
remains on Shift-Cmd-P and stays in command mode when its query is cleared.
Typing `>` in harness search also finds commands.

## Tabs and menus

One harness shows its engine mark; multiple harnesses use the group mark. Returning
to one restores the engine mark. The same rule applies in search and History,
including Recently Closed; a closure retains its engine identity even if the
agent disappears from discovery. Tab names remain editable. Former default names
`New swarm`, `New tab`, and `New Agent` restore as `New Harness` and still take
the first agent's name when opened.

The macOS menus are **Harness, File, Edit, View, History, Models, Machines,
Window, Help**. File groups **New Tab, New Harness, Find Harness, Rename Harness, Close Harness**;
then **Split Right, Split Down, Zoom Pane, Close Pane**. Pin/Unpin and Add Project
are removed from this menu. Machines starts with **Open Machines Manager**, then
linked computers with their status, followed by Link Machine and Refresh Machines.
The manager has a visible **Rename** action on each computer and uses the existing
machine rename API. It reports failures inline and refreshes names in the menu
and pane headers immediately after success. Selecting a computer opens the shared search with its
name filled in; no agent is opened until the user chooses a result.

**Cmd-T** opens a new tab with the shared picker, **Cmd-N** opens Create Harness
directly, and **Cmd-O** finds an existing harness. **Cmd-S** opens Layout.
**Cmd-H/J/K/L** and **Cmd-arrows** focus panes; **Shift-Cmd-arrows** move them.
**Cmd-1…Cmd-9** select tabs in their visible order; missing numbers do nothing.
Cmd-W closes the tab, Shift-Cmd-W closes the focused pane, and Shift-Cmd-T
reopens the last closed view. Unused default-name empty pages are never recorded
in Recently Closed, including pages restored from older builds. Shift-Cmd-N and
shifted H/J/K/L are unbound by default. Configured user bindings retain precedence.
Each tab retains its focused
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

## Latest terminal output

Newly attached, restored, reopened and reconnected panes show the latest output.
Returning to a workspace, reusing an existing pane in another workspace, relayout,
resize, zoom/unzoom and terminal-font changes align visible terminals to the bottom.
The renderer resolves the bottom against the current buffer during layout; a
numeric jump to the previous frame's scroll extent can land hundreds of lines short
when late history or a resize keyframe arrives.

Manual scrollback remains usable while reading an unchanged pane, and an active
Find keeps its selected match. Hidden terminals retain their renderer and consume
output without scheduling paints. Regression fixtures cover delayed history and
reconnects for local and remote sessions, multi-pane resize, retained-pane reuse,
hidden output, and input arriving between output and the next layout.
