# Harness entry and pane controls

Users start with one agent immediately and add panes when useful. A **Harness**
is the tab container and holds one or several agents without a selection basket or a separate group-creation step.
This is the latest product direction; it supersedes earlier swarm and multi-select
proposals in the progress log.

**Agent** is the user-facing name for a session and its actions: Open Agent,
New Agent, Add Agent, Stop Agent, Restart Agent, and Find an agent. Harness
also names the tab container, application, CLI and device. Custom saved names
and protocol identifiers are unchanged.

## Open and New Agent

**Cmd-T / New Harness** and the tab-bar plus open the Harness start page over its
Aurora mesh ground — the panel colour with three dim washes in the app's own
accent, Claude and Codex colours, drawn rather than loaded (no photograph). A long search field, capped at 1120 logical pixels,
has a prominent 64-pixel minimum height and shows **Find an agent** in place of
a large heading. The same **New Agent** creation section used by Cmd-N sits below
search, above the device footer. Search starts compact. Activating it keeps the
field's position, width and 32-pixel outer corners fixed and reveals results and
preview side by side at widths of 700 logical pixels and above. Results scroll
in the space above creation; opening, filtering and closing them does not move
the creation row or device. Escape retains the query. Without a linked machine,
the page retains Open/New actions and New opens machine linking.

The field starts empty and focused so typing works immediately. Typing, clicking
it, or pressing an arrow reveals the same input, results,
highlight, action arrow and keyboard navigation as the Cmd-N picker. Focus alone does not
build a search catalog or reveal results. New Harness refocuses an existing unused
page too. Typing filters immediately; arrows select and Enter opens. Escape or clicking
outside closes the dropdown and hides the caret. The recent-agent list is removed.
The closed page retains only search text and selection: it does not keep a live
search subscription or build a catalog when an unused page closes. Reopening
refreshes results against current app state. Command-mode shortcuts synchronize
the field and results without adding editor rebuilds to arrow navigation.
Opening the dropdown keeps its whole list viewport inside the window. Resizing
or changing text size reveals the highlighted row without changing the selection.
A product strip runs along the footer, the width of the search field, and
links to https://www.autonomous.ai/harness-device: a glass band holding a
cutout of the device (`assets/harness_device.png`, the render with its studio
ground keyed out, so the device floats on the page's own ground), the title
“Meet the Harness device”, the line “A device for your agents — scroll, switch
panes, give voice commands.” and a Learn more pill. 120 points tall, 84 with
the line dropped when the window is short.
Unused default-name empty pages are excluded from Recently Closed.

The titlebar places the bell beside the traffic lights, then the tabs and tab
plus. A single accented **Add Agent** button sits on the right. It and
**Cmd-N** open a combined panel with a focused **Find an agent** field, results
and preview above a compact **New Agent** section. Both sections use an almost-black surface and large
matching headings; the modal search field is blank beneath its heading. There is
no Open Agent footer button. The highlighted row action or Enter opens a result. This supersedes the two-button modal and separate workspace creation
dialog; the New Harness page remains compact until search is activated.

The creation section stays anchored at the panel's bottom while queries and
results change. Results scroll in the space above it. Search does not cover,
push down or reset the creation controls. The main row is **Agent / Project /
Machine / Create**, with three equal-width dropdowns displaying both a category
and its selected value, beside a larger Create button. Defaults are the remembered agent, **New project**, and this
computer. A split inherits the focused agent's machine and project instead.
Project choices are **New project / Local folder… / Remote repository…**.
Local browses the selected machine; Remote shows an inline repository field.
Dropdowns support keyboard navigation and typeahead, and their arrow/Enter keys
never activate search results. **Shift-Cmd-N** focuses the Agent control without
clearing the query. Escape closes an open menu first, then the panel, restoring
terminal focus. From inline search, Shift-Cmd-N collapses results and focuses the creation row
already on the page. Escape there returns focus to its compact search field.

The row wraps on narrow windows or at large text sizes; creation details scroll
within a bounded section. **Options** keeps account and permissions controls
available without expanding the initial form; its collapsed row omits the profile
summary. A pending Codex profile lookup is explained beneath the controls. Loading
a saved engine preference identical to the current selection preserves the loaded
profile and submit readiness. Cached engine availability is
reused when opening the combined surface. No project list is rebuilt from every
agent on each query change. Existing standalone creation entry points retain
their direct-choice dialog and share the same creation and recovery logic.

New creates a unique folder under `~/Harness Projects` without a picker or name
prompt. Remote accepts the existing GitHub HTTPS/SSH URL or `owner/repository`
forms and clones under the same root on the selected machine. Nothing is created
until **Create** is submitted. A prepared folder is reused after a refused launch.
An uncertain launch keeps its original receipt and offers **Check status** and
an explicit **Close**, without cloning or starting again. Search, destination
changes and accidental dismissal are blocked while creating or awaiting status.
Successful creation focuses the new agent, including its requested split.
Remote folder preparation requires the accompanying CLI change; this computer
prepares folders locally and keeps the existing create protocol.

The titlebar button is a 34-point-high pill with generous padding and a 12-point
right margin. Native menu and titlebar hover hints remain removed; accessible
names and shortcut help identify the actions. Workspace modals preserve the
button's normal colors while its actions remain blocked.

The Open popup keeps its full-width **Find an agent** field, single-choice
results and 90% black backdrop. Only the highlighted row shows **Open Agent**,
**Open N Agents**, or **Split right/down**, depending on context.
Both Open and inline start-page search show the same session preview. The Cmd-N
surface can grow to 1120 logical pixels, placing the list and preview side by
side. Narrow windows stack them with a compact preview heading. Both sections
scroll independently; the expanded panel stays within view. Hover selects a
preview without taking typing focus. Enter opens the highlighted result.
Page Up/Down scrolls the preview while retaining the query, focus and selection.
The bindings are configurable in the same Search keymap as result navigation.

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
The creation row retains the requested split position. Shift-Cmd-N focuses it
while search remains available; dismissing the panel returns to the terminal.
The input and result rows share one picker shortcut scope. Tab focus highlights
the row that Enter will open. Arrow navigation and command-mode entry return
focus to the input for continued typing; remapped or unbound navigation/Enter
keys keep their meaning on a focused row. Closing the inline picker releases
focus from the search surface. Escape from inline creation returns focus to the
compact search input.
Native New Agent and Search Commands actions use the focused picker's
actions too. Command search stays in its field; the inline start-page dropdown
closes before focusing its adjacent creation row. Native actions wait for the destination focus tree before
handing keyboard ownership back to Flutter and preserve in-progress search composition.

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
Window, Help**. File groups **New Harness, Add Agent…, Rename Harness, Close Harness**;
then **Split Right, Split Down, Zoom Pane, Close Pane**. Pin/Unpin and Add Project
are removed from this menu. File actions have native system icons, with the same
four-corner Zoom and plain Close cross as the pane header. Machines starts with **Open Machines Manager**, then
linked computers with their status and cached agent count, followed by Link
Machine and Refresh Machines. The menu is at least 500 points wide, with agent
counts in a right-aligned column before the native submenu chevron. Each computer is a submenu of named agents with
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

**Cmd-T** opens the start page and **Cmd-N** opens Add Agent.
**Shift-Cmd-N** focuses creation in the combined panel; Cmd-O is unbound by default. **Cmd-S** opens Layout.
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
