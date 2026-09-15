# Harness entry and pane controls

Users start with one agent immediately and add panes when useful. A tab holds
one or several agents without a selection basket or a separate group-creation step.
This is the latest product direction; it supersedes earlier swarm and multi-select
proposals in the progress log.

**Agent** is the user-facing name for a session and its actions: Open Agent,
New Agent, Add Agent, Stop Agent, Restart Agent, and Find an agent. Harness
remains the application, CLI and device brand. Existing saved names and protocol
identifiers are unchanged.

## Open and New Agent

**Cmd-T / New Tab** and the tab-bar plus open the Harness start page over its
restored lake-at-dusk wallpaper. A long search field, capped at 1120 logical pixels,
has a prominent 64-pixel minimum height and shows **Find an agent** in place of
a large heading. **Open Agent** and accented
**+ New Agent** sit underneath, aligned with the field's left edge. The pill
buttons retain their smaller 48-pixel height and wrap at narrow widths or large
text sizes. The device image and its caption share that same left edge in a footer
32 pixels above the window bottom. The footer stays put when search opens or
closes. Short windows use a small image beside the caption to preserve search space.

Activating search keeps the field's position and width fixed and reveals results and preview
side by side at widths of 700 logical pixels and above. The actions hide while
searching. Results fit the available space above the footer and scroll independently.
Escape restores both actions and retains the query.

The field starts empty and focused so typing works immediately. Typing, clicking
it or Open Agent, or pressing an arrow reveals the same input, results,
highlight, action arrow and keyboard navigation as the Cmd-N picker. Focus alone does not
build a search catalog or reveal results. New Tab refocuses an existing unused
page too. Typing filters immediately; arrows select and Enter opens. Escape or clicking
outside closes the dropdown and hides the caret. The recent-agent list is removed.
The closed page retains only search text and selection: it does not keep a live
search subscription or build a catalog when an unused page closes. Reopening
refreshes results against current app state. Command-mode shortcuts synchronize
the field and results without adding editor rebuilds to arrow navigation.
Opening the dropdown keeps its whole list viewport inside the window. Resizing
or changing text size reveals the highlighted row without changing the selection.
A small product image and caption stay in the footer and link to
https://www.autonomous.ai/harness-device. The bundled image is the official
device image from https://cdn.autonomous.ai/production/ecm/260731/2.webp,
cropped in the viewport so the device is larger and centered. The caption is
“Meet the Harness device”.
The start-page actions use the same pill shape as the titlebar. The device link
and both pairs of New/Open buttons show a hand cursor. Open Agent on the start
page is transparent with a subtle border; New
Harness retains its accent fill.
Unused default-name empty pages are excluded from Recently Closed.

The titlebar places the bell beside the traffic lights, then the tabs and tab
plus. A single accented **Add Agent** button sits on the right. It and
**Cmd-N** open the results and preview immediately beneath a focused
**Find an agent** field, with outlined **Open Agent** and accented
**+ New Agent** below the panel. Enter immediately opens the highlighted result.
This supersedes the compact-first modal; the New Tab page remains compact until
search is activated. Both buttons remain available; Open activates
the selected result and New replaces search with creation. There is no stacked
picker behind creation. Escape dismisses the chooser and restores terminal focus.
The titlebar button is a 34-point-high pill with generous padding and a 12-point
right margin. Native menu and titlebar hover hints remain removed; accessible
names and shortcut help identify the actions. Workspace modals preserve the
button's normal colors while its actions remain blocked.

The creation dialog title and CTA are **New Agent**. Cancel is removed; Escape
and clicking outside dismiss it. Launch-in-progress and uncertain-outcome states
retain their existing safeguards and recovery actions.
Machine and Agent use the same direct-choice layout: up to three buttons, with
**…** only when more options exist. This computer comes first; machines show
local/remote and offline/link status below their names. The first two agent slots
are Codex and Claude Code; the third begins as Cursor. Choosing from **…** replaces
the third slot, and that option stays available while switching between the first
two. All options remain in **…**. Selection uses an accent-tinted fill and check;
a separate outline shows keyboard focus. The form is 760 logical pixels wide.
Machine choices stay on one row; narrow windows and larger text move excess
choices into **…**, keeping the selected machine visible. Agent choices can wrap.
Long custom names have their full text in a tooltip.
Selecting the current machine again preserves the chosen folder. One healthy
local machine still needs no machine selector.
The folder control receives initial keyboard focus, so Enter opens its chooser.
A successful keyboard folder choice focuses the enabled New Agent action;
cancellation or failure returns focus to the folder control. If a required Codex
account lookup is still pending, focus stays on the folder instead of a disabled
submit action. Completing that lookup does not steal focus.

Working folder has three visible choices: **New / Local / Remote**. Local is
initially selected and browses the selected machine. New creates a unique folder
under `~/Harness Projects` without a picker or name prompt. Remote accepts the
existing GitHub HTTPS/SSH URL or `owner/repository` forms inline and clones under
the same root on the selected machine. Nothing is created until New Agent is
submitted. A prepared folder is reused after a refused launch. An uncertain
launch keeps the original receipt and offers Check status instead of cloning or
starting again. Remote folder preparation requires the accompanying CLI change;
this computer prepares folders locally and keeps the existing create protocol.

The **…** menus support typing a name to highlight a choice. Enter
selects it; Escape returns to the field without changing the value. These keys
also work immediately after opening the menu, before its first frame.

The Open popup keeps its full-width **Find an agent** field, single-choice
results and 90% black backdrop. Only the highlighted row shows **Open Agent**,
**Open N Harnesses**, or **Split right/down**, depending on context.
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
The visible New Agent action or Shift-Cmd-N while choosing a split replaces
search with creation in that split position; dismissing creation still returns directly to the terminal.
The input and result rows share one picker shortcut scope. Tab focus highlights
the row that Enter will open. Arrow navigation and command-mode entry return
focus to the input for continued typing; remapped or unbound navigation/Enter
keys keep their meaning on a focused row. Closing the inline picker releases
focus from the entire surface, so dismissing New Agent cannot restore a caret.
Native New Agent and Search Commands actions use the focused picker's
actions too. Command search stays in its field, and creation closes its dropdown
before opening the form. Native actions wait for the destination focus tree before
handing keyboard ownership back to Flutter and preserve in-progress search composition.

Rename Tab has one title and an unlabeled, accessible name field, with the
current name selected for immediate typing. Muted focus colors and pill-shaped
Cancel/Rename actions match the entry UI. Blank names stay in the dialog; the
80-character count appears only near the limit. Its 60% veil covers the canvas.
Native tabs consume the whole double-click sequence so opening Rename Tab does
not also trigger the window's titlebar zoom behavior.

## Tabs and menus

One harness shows its engine mark; multiple agents use four separate outlined
tiles, matching the native square.grid.2x2 symbol. An empty tab uses a plain plus.
Only one unused **New Tab** is kept. New Tab from the plus, File menu,
Cmd-T or command search selects that existing page, even at the tab limit.
Restoration collapses duplicate unused pages from older builds, preferring the
selected one; named tabs and saved layouts are retained.
Tab close marks appear only on hover or keyboard focus, retaining their space
and accessible actions while idle. Returning
to one restores the engine mark. The same rule applies in search and History,
including Recently Closed; a closure retains its engine identity even if the
agent disappears from discovery. Tab names remain editable. Former default names
`New swarm`, `New tab`, `New Agent`, and `New Harness` restore as `New Tab` and still take
the first agent's name when opened.

The macOS menus are **Harness, File, Edit, View, History, Models, Machines,
Window, Help**. File groups **New Tab, Add Agent…, Rename Tab, Close Tab**;
then **Split Right, Split Down, Zoom Pane, Close Pane**. Pin/Unpin and Add Project
are removed from this menu. File actions have native system icons, with the same
four-corner Zoom and plain Close cross as the pane header. Machines starts with **Open Machines Manager**, then
linked computers with their status and cached agent count, followed by Link
Machine and Refresh Machines. Each computer is a submenu of named agents with
engine icons. Selecting an agent opens its exact machine/agent identity, reusing
an existing pane when present. The submenu retains Find Agents for the full
search. Empty/unavailable lists are explicit; unknown counts are not shown as
zero. Menus use existing cached discovery, with no fetch on opening. A stale
agent or unlinked machine cannot redirect a menu action.
The manager has a visible **Rename** action on each computer and uses the existing
machine rename API. It reports failures inline and refreshes names in the menu
and pane headers immediately after success. Selecting a computer opens the shared search with its
name filled in; no agent is opened until the user chooses a result.

**Cmd-T** opens the start page and **Cmd-N** opens Add Agent.
**Shift-Cmd-N** remains a direct creation shortcut; Cmd-O is unbound by default. **Cmd-S** opens Layout.
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
harness, preserving project files and saved conversation history. The existing
`agent_delete` protocol remains unchanged. It is not Pause and promises no live
process suspension/resume. Close Pane removes only this view and leaves the agent
running. Restart uses the same circular-arrow icon and existing restart action as
the agent menu. It relaunches the same harness, resuming the conversation where
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
