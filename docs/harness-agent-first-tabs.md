# Harness entry and pane controls

Users start with one harness immediately and add panes when useful. A tab holds
one or several harnesses without a selection basket or a separate group-creation step.
This is the latest product direction; it supersedes earlier swarm and multi-select
proposals in the progress log.

## Open and New Harness

**Cmd-T / New Tab** and the tab-bar plus open the Harness start page. Its solid
background matches the selected tab. The centered title and search controls sit
lower with generous empty space. The field is no wider than 640 logical pixels,
with **Open Harness** and accented **+ New Harness** buttons underneath.

The field starts empty and unfocused. Clicking it or Open Harness reveals the
same input, results, highlight, action arrow and keyboard navigation as Cmd-O.
Typing filters immediately; arrows select and Enter opens. Escape or clicking
outside closes the dropdown and hides the caret. The recent-agent list is removed.
The closed page retains only search text and selection: it does not keep a live
search subscription or build a catalog when an unused page closes. Reopening
refreshes results against current app state. Command-mode shortcuts synchronize
the field and results without adding editor rebuilds to arrow navigation.
A small product image and introduction sit well below the controls and link to
https://www.autonomous.ai/harness-device. The bundled image is the official
product photo from https://cdn.autonomous.ai/production/ecm/260731/2.webp.
Unused default-name empty pages are excluded from Recently Closed.

The titlebar places the bell beside the traffic lights, then the tabs and tab
plus. Explicit **New Harness** and **Open Harness** buttons sit on the right.
There is no floating +. Cmd-N opens creation directly; Cmd-O opens existing-work
search. Each has its own popup, with no creation CTA or “or” divider in search,
no Back to Search button in creation, and no stacked dialog on dismissal.
The Flutter titlebar uses the same compact accent/secondary button treatment as
AppKit, inherits the app's font, and exposes current shortcut hints on hover.
The creation dialog title and CTA are **New Harness**. Cancel is removed; Escape
and clicking outside dismiss it. Launch-in-progress and uncertain-outcome states
retain their existing safeguards and recovery actions.
The folder control receives initial keyboard focus, so Enter opens its chooser.
A successful keyboard folder choice focuses the enabled New Harness action;
cancellation or failure returns focus to the folder control. If a required Codex
account lookup is still pending, focus stays on the folder instead of a disabled
submit action. Completing that lookup does not steal focus.

The Open popup keeps its full-width **Find a harness** field, single-choice
results and 90% black backdrop. Only the highlighted row shows **Open Harness**,
**Open N Harnesses**, or **Split right/down**, depending on context.
Secondary text is **project · branch · machine**. Missing metadata is omitted
and the containing workspace name is not repeated.
The Commands footer stays removed; Shift-Cmd-P and typing `>` expose commands.
An explicit Cmd-N while choosing a split replaces search with creation in that
split position; dismissing creation still returns directly to the terminal.
Native New Harness and Search Commands actions use the focused search field's
actions too. Command search stays in that field, and creation closes its dropdown
before opening the form. Native actions wait for the destination focus tree before
handing keyboard ownership back to Flutter and preserve in-progress search composition.

## Tabs and menus

One harness shows its engine mark; multiple harnesses use the group mark. Returning
to one restores the engine mark. The same rule applies in search and History,
including Recently Closed; a closure retains its engine identity even if the
agent disappears from discovery. Tab names remain editable. Former default names
`New swarm`, `New tab`, and `New Agent` restore as `New Harness` and still take
the first agent's name when opened.

The macOS menus are **Harness, File, Edit, View, History, Models, Machines,
Window, Help**. File groups **New Tab, New Harness, Open Harness, Rename Harness, Close Harness**;
then **Split Right, Split Down, Zoom Pane, Close Pane**. Pin/Unpin and Add Project
are removed from this menu. Machines starts with **Open Machines Manager**, then
linked computers with their status, followed by Link Machine and Refresh Machines.
The manager has a visible **Rename** action on each computer and uses the existing
machine rename API. It reports failures inline and refreshes names in the menu
and pane headers immediately after success. Selecting a computer opens the shared search with its
name filled in; no agent is opened until the user chooses a result.

**Cmd-T** opens the start page, **Cmd-N** opens New Harness
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
right/bottom edge plus controls continue to open search at that split position, and
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

A relayout request also reaches panes whose dimensions are unchanged, including
neighbors of an added pane and a reapplied preset. Returning to live output cancels
in-flight scroll animation and dial inertia, so their next tick cannot pull the
viewport back into history. Focused tests reproduce both failures before the fix.

On macOS, Codex can clear history and repaint in several output frames after
resize. The renderer now corrects the tail before publishing the shortened
scroll extent, preventing the OS from starting a bounce toward the old origin.
A platform-specific regression reproduces the jump to offset zero before this
fix and passes for macOS and Linux afterward.
