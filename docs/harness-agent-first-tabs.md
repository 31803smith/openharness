# Harness entry and pane controls

Users start with one agent immediately and add panes when useful. A **Harness**
is the tab container and holds one or several agents without a selection basket or a separate group-creation step.
This is the latest product direction; it supersedes earlier swarm and multi-select
proposals in the progress log.

**Agent** is the user-facing name for a session and its actions: Open Agent,
New Agent, Stop Agent, Restart Agent, and Find an agent. Harness
also names the tab container, application, CLI and device. Custom saved names
and protocol identifiers are unchanged.

## UI preference

The user prefers minimal, neat UI: **less is better**. Use short, direct labels.
Avoid repeated headings, promotional taglines and descriptions of self-evident
controls. Show a choice's name and useful preview; add explanation only when it
helps someone decide or recover from an error. Prefer whitespace and restrained
surfaces over extra rules and nested cards. Apply this consistently without
waiting for the user to request copy removal one control at a time.
Tooltips must add information, never repeat a visible label.
Each choice row has exactly one selected option. Only selection gets an outline;
keyboard focus uses a quiet fill so it cannot look like a second selection.
Choice tiles use the border as their selection marker, without a checkmark.
More menus show only the remaining choices, without repeating the visible tiles.
The More tile uses a grid icon for engines and a monitor for machines; selected
alternatives use their own icon.
Icon buttons share a quiet rounded background on hover and keyboard focus.
Apply this to native tab close, new-tab and notification icons as well as
Flutter controls. Disabled icons do not highlight; decorative icons stay inert.

Action order is **New → Open** in the titlebar, File menu and both split controls.
The **New Harness page is the deliberate exception: Open → New** below search.

## Customize Harness

The New Harness page defaults to the selected tab's solid fill, using the same
workspace palette color. **Customize Harness** is a pill at the bottom right on
Default. With any wallpaper selected, it becomes a compact circular pencil
button with the same tooltip and accessible label; switching back restores the
full label immediately.
It opens a right-hand pane with **Wallpaper / Appearance / Terminal** sections.
Wide windows keep the page beside it; narrow windows overlay the pane without
squeezing the search controls. Closing it restores focus to the Customize button
and preserves the query. Escape closes an open settings menu before the pane.

Wallpaper offers **Default, Aurora, Lake, Silk, Threads and Constellation**.
The choices appear directly below the tabs, with no repeated heading or intro.
The lake and generated images are restored from the existing asset history;
Aurora reuses the existing mesh. Choices apply immediately, persist under
`harness_start_background`, and affect only empty Harness pages. Default stays
in step with palette changes. Unknown saved choices fall back to Default.

Appearance and Terminal move out of Settings into this pane, reusing their
existing palette, UI font/size, terminal scheme, font/size, preview and reset
controls and stores. Settings now starts at Usage. The device footer stays fixed
above the bottom-right button while search opens and closes. No uploads,
background downloads, theme editor or new dependency is added.
Appearance shows **Color palette** with names only, then **Text** with font and
size controls. Terminal has **Colors, Font, Size**, a working preview and
**Reset font**. Repeated section titles, helper paragraphs, palette descriptions,
terminal cell metrics and unnecessary card layers are removed.

Validation: 46 affected Flutter tests pass, including wallpaper persistence and
keyboard selection, focus restoration, dropdown dismissal, existing-agent entry,
moved settings, palette propagation, terminal scale isolation and narrow-window
rendering. All 17 changed Dart/test files analyze cleanly. Captures at 1280×800,
880×560 and 600×680 with 1.7× text are in
`/private/tmp/harness-customize-captures`.
The macOS Release build and deep/strict signature verification pass; all four
restored image assets are present in the bundle.

## Open and New Agent

**New Agent (Cmd-N)** opens the dedicated creation dialog. **Open Agent (Cmd-O)**
opens existing-agent search with results and preview immediately. The titlebar
and File menu expose both actions. This replaces the combined Add Agent form
at the user's request; there is no embedded creation section in search or on
the New Harness page. Custom key bindings retain precedence. The internal
`agent.add` command and native `addAgent` action remain stable, labeled Open Agent.
Agent actions share **+** for New and **↗** for Open, including the native menu
and titlebar. Find fields keep the magnifying glass for search.

**Cmd-T / New Harness** opens the start page with a long, initially compact
search field and **Open Agent / New Agent** buttons below it. The field is capped
at 1120 logical pixels, has a 64-pixel minimum height and shows **Find an agent**.
Its position, width and 32-pixel outer corners stay fixed when results open.
The input, results and preview share one palette surface in both states, with
a subtle outer edge and shadow. Soft rounded selection and whitespace separate
content without internal dividing lines or a darker preview column.
Results and preview share the space above the fixed device footer. Typing,
clicking or pressing an arrow opens search; focus alone does not build its catalog.
Escape closes results and retains the query. The default background matches the selected tab, and the device
link stays above the customization button. A compact studio photograph shows
the device at a larger size, with **Meet the Harness device** typeset beside it.
The tile is 360 × 180 pixels (300 × 150 in shorter windows), has no outline,
description or separate Learn more action, and opens the device page as one link.
New without a linked machine opens machine linking.

Open Agent uses the same continuous search surface as New Harness, with
**Find an agent** inside the input and no separate heading or inset outline.
It sits over a 90% black canvas veil. Results appear immediately;
arrows select and Enter or a row click opens the agent. There is no footer
button or New Agent form. Results and preview sit side by side from 700 logical
pixels; narrower windows stack them. Both scroll independently. Hover updates
the preview without taking typing focus. Page Up/Down scrolls the preview while
retaining the query and selection. Native menus and the titlebar retain normal
colors while modal actions are blocked.

New Agent uses the same generous width as Open Agent. Three stacked sections
lead through **Choose an engine**, **Where will this agent run?**, and **Which project will
this agent work in?** Each row has four equal tiles. Codex, Claude Code, and
OpenCode occupy the first three engine slots. The fourth is **More ⌄**; choosing
another engine replaces its label and icon, never adds a fifth tile.

Machines follow the same pattern: this computer first, then online machines,
then unavailable ones in the dropdown. The first three remain direct choices.
The local computer says **This machine**. A monitor or crossed-out monitor
indicates availability; there are no repeated Offline labels. An alternative
machine occupies the fourth dropdown tile. Smaller windows and larger text
wrap to two columns or one, with the body scrolling above the fixed footer.

Projects offer **New project / Local / Git / Recent ⌄**. New selects an empty
project without creating anything yet. Local opens the folder picker on the
chosen machine; Git opens a small URL dialog; Recent lists that machine’s
previous projects. The selected folder or repository name appears only inside
its tile, without a repeated full path or URL below. Every new dialog defaults
to New project; Recent never preselects a saved folder. Choices survive machine
switches only within that open dialog. An explicitly supplied project from a
split entry and a prepared-folder retry retain their destination. New folders use
`~/harnesses/agent-1`, `agent-2`, …. Switching engines keeps the project.

A small settings icon at the bottom left reveals Codex profiles and permissions.
The sole ordinary footer action is a large bright **Create** button. Escape or
an outside click dismisses. No hover hints repeat labels already on screen.
Icon-only controls retain accessible names. A late saved preference equal to
the selected engine preserves loaded profile readiness. Failure keeps the
choices and prepared folder; an uncertain launch retains its receipt and offers
**Check status** and **Close** without cloning or starting again. Success focuses
the new agent.

Split Right/Down opens the existing-agent picker for that position. Its **+ New Agent**
input action (with tooltip), or Cmd-N, replaces the picker with creation and preserves the split,
machine and project. Dismissing creation returns directly to the original pane.
Ordinary New Agent prefers this computer. Search and creation never stack.
The restored flows pass 203 affected Flutter tests, 96 native keyboard checks,
407 hidden AppKit checks, and analysis of all changed Dart/test files. Normal
and larger-text render fixtures were inspected; live app inspection remains
unavailable before installation of this change.

Working sessions lead with the current observed request and latest activity.
Idle sessions lead with an existing saved response or the latest response seen
in the live stream. Pending questions appear prominently. Recent requests and
saved responses without a shared turn identity are labeled separately; old
responses never masquerade as the current turn's answer. Groups show readable
member excerpts, waiting first, and build only visible members. Offline content
is labeled as saved; missing content stays explicit.

No previews generate summaries or start models. The bounded shared cache uses
only existing `agent_recent` content and ordinary session events. It does not
read full histories or attach terminals. Arrow selection reads cached records;
background refresh fills cold records without blocking editing. Details and
limits are recorded in [the preview design](harness-search-preview.md).
Secondary text is **project · branch · machine**, with one small muted Git branch
mark immediately before the branch in search and pane headers. Missing metadata is omitted
and the containing workspace name is not repeated.
The Commands footer stays removed; Shift-Cmd-P and typing `>` expose commands.
The input and result rows share one picker shortcut scope. Tab focus highlights
the row that Enter opens. Arrow navigation and command-mode entry return focus
to the input; custom bindings retain their meaning. Native New Agent closes the
picker before opening creation and restores keyboard ownership to Flutter.

Pane connection states (Connecting, Restoring and Reconnect) follow the session
name on the left. The project, branch and machine retain the same space on the
right across status changes. Reconnect keeps its existing terminal reconnection
action and error tooltip.

Rename Harness has one title and an unlabeled, accessible name field, with the
current name selected for immediate typing. Muted focus colors and pill-shaped
Cancel/Rename actions match the entry UI. Blank names stay in the dialog; the
80-character count appears only near the limit. Its 60% veil covers the canvas.
Native tabs consume the whole double-click sequence so opening Rename Harness does
not also trigger the window's titlebar zoom behavior.

## Tabs and menus

One agent shows its engine mark; multiple agents use four separate outlined
tiles, matching the native square.grid.2x2 symbol. An empty tab uses a plain plus.
Only one unused **New Harness** is kept. New Harness from the plus, File menu,
Cmd-T or command search selects that existing page, even at the tab limit.
Restoration collapses duplicate unused pages from older builds, preferring the
selected one; named tabs and saved layouts are retained.
Tab close marks appear only on hover or keyboard focus, retaining their space
and accessible actions while idle. Returning
to one restores the engine mark. The same rule applies in search and History,
including Recently Closed; a closure retains its engine identity even if the
agent disappears from discovery. Tab names remain editable. Former default names
`New swarm`, `New tab`, `New Tab`, and `New Agent` restore as `New Harness` and still take
the first agent's name when opened.

The macOS menus are **Harness, File, Edit, View, History, Models, Machines,
Window, Help**. File groups **New Harness, New Agent…, Open Agent…, Rename Harness, Close Harness**;
then **Split Right, Split Down, Zoom Pane, Close Pane**. Pin/Unpin and Add Project
are removed from this menu. File actions have native system icons, with the same
four-corner Zoom and plain Close cross as the pane header. Machines starts with **Open Machines Manager**, then
linked computers with their status and cached agent count, followed by Link
Machine and Refresh Machines. History and Machines fit their visible labels,
with metadata in a right-aligned column and no fixed minimum width or empty
wide span. Long names truncate to keep the menus compact. Machine counts sit
before the native submenu chevron. Each computer is a submenu of named agents with
engine icons. Selecting an agent opens its exact machine/agent identity, reusing
an existing pane when present. The submenu retains Find Agents for the full
search. Empty/unavailable lists are explicit; unknown counts are not shown as
zero. Menus use existing cached discovery, with no fetch on opening. Native
inventory updates are separate from tab updates, so switching tabs does not
resend or decode the agent list. Names, counts and availability still refresh
when they change; leaving the workspace clears the list. A stale
agent or unlinked machine cannot redirect a menu action.
The manager has a visible **Rename** action on each computer and uses the existing
machine rename API. It reports failures inline and refreshes names in the menu
and pane headers immediately after success. Find Agents opens the shared search
with the computer's name filled in; no agent is opened until the user chooses a result.

**Cmd-T** opens the start page, **Cmd-N** opens New Agent and **Cmd-O** opens
Open Agent. **Cmd-S** opens Layout.
**Cmd-R** splits right and **Cmd-D** splits down, opening the shared picker for
that position. Refresh Machines stays in the Machines menu and command search,
without a default chord. The developer-only Debug shortcut is Shift-Cmd-D.
Pressing the configured Layout key again cycles choices without applying them;
Enter applies the highlighted choice and Escape cancels. Plain digits choose
directly, while modified digits and arrows cannot accidentally apply a shape.
Layout cards keep fixed diagram bounds as the highlight moves. Larger text gets
wider cards and readable labels, with arrow navigation following the rendered
rows and scrolling the selected choice into view when necessary.
Two panes offer only Columns and Rows. Three and four panes add spanning main
panes and explicit rows/columns; five adds balanced 3+2 and 2+3 rows, a central
main pane, and main-plus-grid choices. Larger counts offer balanced grids, with
main-plus-grid choices through nine panes. Every offered shape fills the canvas;
equivalent rectangles are deduplicated at each count through the 64-pane limit.
Automatic and older grid IDs still restore saved geometry, but do not appear as
duplicate cards. Their matching explicit card is highlighted when available.
**Cmd-H/J/K/L** and **Cmd-arrows** focus panes; **Shift-Cmd-arrows** move them.
**Cmd-1…Cmd-9** select tabs in their visible order; missing numbers do nothing.
Cmd-W closes the tab, Shift-Cmd-W closes the focused pane, and Shift-Cmd-T
reopens the last closed view. Unused default-name empty pages are never recorded
in Recently Closed, including pages restored from older builds.
Shifted H/J/K/L are unbound by default. Configured user bindings retain precedence.
Each tab retains its focused
pane when switching away and back. Closing views
keeps agent runtimes alive. Stored layout formats and internal command IDs remain
compatible.

Switching between panes or tabs, closing them, or moving between zoomed panes
transfers keyboard and text input to the ready retained view before the next
rendered frame. Its existing terminal, composer or
Find field receives the next key with its draft and selection intact. Blank
pages release the previous terminal immediately and focus the start-page search
without showing results until interaction. A connecting composer releases the old input connection and receives
focus once ready. Dialogs keep input while background destinations or connection
state change; dismissal returns it to the current destination without restoring an
older agent's focus.

## Pane chrome

The left side contains only the agent icon and session name. The right side
shows **folder • branch • machine**, omitting unavailable folder/branch data.
Long details truncate, with full context in the session-name tooltip.

Hovering anywhere on the header replaces the details with small, muted controls:
**Zoom Pane, Restart Agent, Stop Agent, Close Pane**, with **Keyboard** first for remote sessions. Keyboard
focus also reveals the controls. The title keeps the same space during the swap,
and hovering retains the terminal renderer. Stop uses a plain filled square
and an explicit confirmation: it ends the engine process and removes the active
agent, preserving project files and saved conversation history. The existing
`agent_delete` protocol remains unchanged. It is not Pause and promises no live
process suspension/resume. Close Pane removes only this view and leaves the agent
running. Restart uses the same circular-arrow icon and existing restart action as
the agent menu. It relaunches the same agent, resuming the conversation where
supported; failures and a fresh-session fallback are shown in a snackbar. It is
disabled for unavailable or unlinked machines. Keyboard toggles the remote message composer.

Resize grips are invisible while idle and appear on divider hover, keyboard
focus or active drag. Their hit targets and resize behavior stay the same. The
right/bottom edges reveal two actions in a small capsule: **+ New Agent** and
**↗ Open Agent**. On the right they stack; along the bottom they sit side by side.
Both name the split direction in their tooltip. New opens creation directly with
the hovered pane's machine/project; Open shows existing-agent search for that
position. Hovering and crossing between the buttons preserves keyboard focus,
terminal views and neighbor geometry. Keyboard split commands remain available.

The edge change passes 47 split, resize and creation-recovery checks, including
both directions for New and Open and dismissal back to the intended terminal.
Analysis of the four changed Dart/test files is clean. Logs:
`/private/tmp/harness-agent-edge-tests.log` and
`/private/tmp/harness-agent-edge-analyze.log`.

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

Find takes keyboard and text input as soon as its shortcut or native action is
invoked, including before its first frame. Only a focused, visible pane prepares
a dormant editor; it stays hidden and unfocusable, with no search index, until
requested. Immediate text, composition and Escape belong to Find, not the agent.
Closing Find returns keyboard and text input to the retained terminal or visible
message composer immediately, without waiting for another frame. The next key
cannot be lost in the closing search field or replace its remembered query.

A relayout request also reaches panes whose dimensions are unchanged, including
neighbors of an added pane and a reapplied preset. Returning to live output cancels
in-flight scroll animation and dial inertia, so their next tick cannot pull the
viewport back into history. Focused tests reproduce both failures before the fix.

On macOS, Codex can clear history and repaint in several output frames after
resize. The renderer now corrects the tail before publishing the shortened
scroll extent, preventing the OS from starting a bounce toward the old origin.
A platform-specific regression reproduces the jump to offset zero before this
fix and passes for macOS and Linux afterward.
