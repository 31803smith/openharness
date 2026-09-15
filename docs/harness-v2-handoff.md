# Harness v2: goal, plan, and continuation handoff

Updated September 15, 2026. Resume on current **main**, preserve local work, and
commit/push completed changes frequently as the user requests.

This is the current continuation guide. The detailed UI contract is
[Harness entry and pane controls](harness-agent-first-tabs.md). Together they
supersede conflicting historical picker, toolbar, menu, shortcut and onboarding
directions. Historical receipts remain in [the progress archive](harness-v2-progress.md)
and Git; the preceding complete handoff is available at **d5785d6**.
Old screenshots, test expectations and saved bundles are not the current UI.

## Goal and status

Build the best everyday workspace for people directing persistent AI agents:
a fast, polished, keyboard-first **agentic browser**, with each tab representing
a Harness containing agents. The user describes it as a “super terminal” for the intelligence age.
Developers should feel the speed, predictability and familiar habits of a great
terminal/editor while working with several agents across real machines and
projects. They should keep their place and know exactly which agent receives
their next instruction.

The product is **Harness**; V2 is the internal UI/UX project name. This is a
working desktop preview, not a completed release. Study useful native Safari,
Chrome and developer-tool behavior, and turn findings into justified improvements
rather than more surfaces. First use, navigation, input correctness and latency
matter more than feature count.

The broader goal is **unfinished**. Real first-use completion, current native
interaction, real remote reconnect and Linux-host qualification still need
evidence. **Native latency benchmarking is explicitly deferred by the user.**
Do not run it, resume calibration when the console unlocks, or interrupt the
user for a benchmark window.

## Current product contract

### September 15 continuation checkpoint

- The user renamed the session concept to **Agent**: Open/New/Add/Stop/Restart
  Agent, Find an agent, counts and recovery copy throughout Flutter and native
  menus. **Harness** now names the tab container as well as the app/device/CLI:
  New Harness, Rename Harness, Close Harness, and navigation/help labels. Custom
  names and wire IDs stay; the old New Tab default restores as New Harness.
- **Current refinement:** Cmd-N opens the result list and preview immediately.
  Large **Find an agent** and **New Agent** headings sit on almost-black panels;
  the modal field has no hint and the redundant Open Agent footer is removed.
  Creation has equal-width Agent / Project / Machine dropdowns and a larger Create
  button. Options no longer shows the collapsed profile summary.
- New Harness includes the same creation row above its fixed device footer.
  Search stays compact until activated, then expands with the same rounded outer
  corners. Query/result changes leave creation and the device in place. From
  inline search, Shift-Cmd-N focuses the adjacent creation row; Escape returns to
  the compact field. No-machine New still opens machine linking.
- Fixed a reproduced Create-button race: a late saved engine preference equal to
  the active engine reset profile readiness without remounting the loaded field.
  The loaded profile and readiness now survive; pending lookups have visible copy.
- Connection status follows the session name on the left, preserving the project,
  branch and machine's width on the right. Machines has a wider native menu and
  right-aligned agent counts before its submenu chevrons.
- The compact form reuses creation, folder preparation, account/engine checks
  and uncertain-outcome recovery. Defaults are the remembered agent, New project
  and this computer; splits inherit their source machine/project. Project offers
  New project, Local folder and Remote repository. Cached engine checks are reused;
  building a query does not scan agent metadata for project suggestions.
- Current refinement verification: **138 Flutter checks pass**, covering the
  combined/inline entry, larger-text rendering, profile readiness, launch/recovery,
  shortcut routing, startup/linking and connection-status geometry. **388 isolated
  AppKit checks pass**, including hidden native window layout and Machines counts.
  All 15 changed Dart/test units analyze cleanly. The Release build and staged
  bundle pass deep/strict codesign verification. Logs:
  `/private/tmp/harness-entry-polish-final-tests.log`,
  `/private/tmp/harness-entry-polish-analyze.log`,
  `/private/tmp/harness-entry-polish-native.log`,
  `/private/tmp/harness-entry-polish-build.log`.
  Inspected captures: `/private/tmp/harness-entry-polish-picker` and
  `/private/tmp/harness-entry-polish-captures`. The update is installed as **8873f27** and running; live window inspection
  remains unavailable. The receipt is `/private/tmp/harness-entry-polish-install.json`.
- Verification: the 56 navigation/picker checks, 27 creation/engine checks and
  54 combined recovery/render checks pass (overlapping suites). Captures at
  1280×900, 760×760 and 600×680 with double text were inspected; six palettes and
  normal/double text render without overflow. Logs:
  `/private/tmp/harness-composer-picker-tests.log`,
  `/private/tmp/harness-composer-creation-tests.log`,
  `/private/tmp/harness-composer-final-tests.log`. The final focus/folder pass
  adds 40 passing checks after cleanup in
  `/private/tmp/harness-composer-final-focus-tests.log`; the analyzer reports
  no issues in `/private/tmp/harness-composer-final-analyze.log`.
  Captures: `/private/tmp/harness-composer-captures` and
  `/private/tmp/harness-composer-surfaces`.
- The Harness labels and picker fill pass 96 affected Flutter tests plus 12
  render checks across six palettes and two text sizes. Changed Dart files
  analyze cleanly. The exported-keymap fixture, 96 native keyboard checks and
  404 isolated AppKit checks pass. Graphite picker captures at normal and double
  text size were inspected. Logs: `/private/tmp/harness-label-action-tests.log`,
  `/private/tmp/harness-label-action-analyze.log`,
  `/private/tmp/harness-label-action-native.log`,
  `/private/tmp/harness-label-action-render.log`. Captures:
  `/private/tmp/harness-label-action-captures`.
- Standalone creation entry points retain the 760-pixel direct-choice form.
  The workspace uses the combined panel described above, up to 1120 pixels wide.
- Working folder now offers **New / Local / Remote**. New creates a unique
  project under `~/Harness Projects`; Local browses the selected machine;
  Remote clones a GitHub repository onto that machine. The standalone form starts
  on Local; the new compact row defaults to New project. Folder preparation begins
  only on submit. A known refused launch retains its prepared folder for retry.
  Local works with the existing daemon protocol. Remote preparation needs this
  checkout's accompanying CLI change; no real daemon was updated or restarted.
- Machines is a native submenu tree with cached counts, names and engine icons.
  Selection uses both machine and agent IDs. Existing views are revealed, stale
  destinations are refused, and opening menus does no network work.
- **bef8cd6** removes the full agent inventory from native tab updates. A
  separate cached `machinesState` message refreshes visible menu data only when
  it changes. A 512-agent regression reproduced the old resend and now confirms
  six tab switches send no inventory, while renames and retained-pane
  availability still update it. 28 affected Flutter checks passed, followed by
  four focused checks covering availability and menu clearing; changed files
  analyze cleanly. 387 hidden AppKit checks passed, including retained menu
  controls across tab updates. No latency measurement was attempted.
  Logs: `/private/tmp/harness-machine-menu-isolation.log`,
  `/private/tmp/harness-machine-menu-isolation-final.log`,
  `/private/tmp/harness-machine-menu-isolation-analyze.log`,
  `/private/tmp/harness-machine-menu-isolation-native.log`.
- Verification: 339 affected Flutter tests, 57 CLI tests, TypeScript checking,
  96 native keymap checks and 403 AppKit checks pass. No real agents were launched
  or used for input tests, and no native latency benchmark was run. Captures:
  `/private/tmp/harness-agent-folder-captures` and
  `/private/tmp/harness-agent-picker-captures`.

Saved and pushed to `origin/main`: **9d0150d** (remote project preparation),
**e049348** (Agent terminology, creation and machine menus), **10811c3** (final
validation cleanup). The 339-test pass was followed by six passing focused
checks after the analyzer cleanup; changed Dart files now analyze without issues.

**8873f27 is installed and running at the supported preview path.** The user
confirmed Quit Harness, but exact process lookup still found the old PID 68117.
CUA could not reach that window or its Quit action. The saved four-Harness layout
was backed up before sending SIGTERM to that exact remaining preview process.
The process exited; only then was the verified staged bundle swapped into place.
The installed bundle passes deep/strict codesign verification. CUA launched it
at the supported path and a new exact process, PID 71516, remains running.

The saved layout, Harness identities and active Harness remain unchanged from
the backup. The old c0fd824 bundle and layout are retained under
`desktop/build/macos/Build/Products/Release/.harness-before-entry-polish-irjhhr23/`.
The receipt is `/private/tmp/harness-entry-polish-install.json` (also copied to
`/private/tmp/harness-agent-preview-install.json`). Status is
**installed-running-ui-unverified**: `cgWindowNotFound` persists after relaunch
and resetting the app-control connection. Do not claim visual restoration or
current live interaction checks passed. No real agents were created, stopped or
sent input. No daemon or firmware was restarted or upgraded.

The bundle was built from df75157; rebase to 8873f27 preserved the entire desktop
tree byte for byte. Incoming CLI question/recap and dial firmware 0.0.69 changes
were preserved on main. The UI commit is pushed.

The combined panel is saved and pushed as **c0fd824**. Its Release build succeeds
and passes deep/strict codesign verification before and after staging. Prepared:
`/private/tmp/harness-pane-controls-release/Build/Products/Release/Harness.app`.
Build log: `/private/tmp/harness-composer-release.log`. The incremental build
left a stale outer seal; App.framework verified independently, and refreshing
the ad-hoc outer signature restored full verification.

**Previous live verification: c0fd824.** The user quit normally; exact process
lookup confirmed the supported preview was stopped before the swap. CUA reopened
that path and showed all four saved Harnesses, the original active Harness and
its panes. Add Agent opened the combined **Find an agent** / results / preview
panel above **New agent**, with **Agent / Project / Machine / Create** and Options.
No agents were created, stopped or sent input. Keyboard/dropdown automation
remained inconclusive; widget interaction and recovery checks cover those paths.

The previous **454544a** bundle is retained at
`desktop/build/macos/Build/Products/Release/.harness-before-composer-_5b2o2zm/Harness.app`.
Its sibling `swarm-layout.json` backs up the flushed four-Harness layout.
`/private/tmp/harness-agent-preview-install.json` records the completed install;
the previous receipt is `/private/tmp/harness-agent-preview-before-composer.json`.

Incoming main work was preserved, including terminal theme synchronization
(4c7af5e), Codex question detection (12a63a9), and CLI status cleanup (afc9e77).
No real daemon or firmware was updated. Earlier rebased checks passed 17 desktop
dial/creation/menu tests and 40 CLI input tests. Earlier build/test logs:
`/private/tmp/harness-agent-rebased-release.log`,
`/private/tmp/harness-agent-rebased-checks.log`,
`/private/tmp/harness-agent-rebased-cli-tests.log`,
`/private/tmp/harness-agent-ui-regressions.log`,
`/private/tmp/harness-agent-final-checks.log`,
`/private/tmp/harness-project-folder-cli-tests.log`,
`/private/tmp/harness-agent-menus-native.log`.

**Previous live verification: 454544a.** The user quit normally; the exact
process was confirmed stopped before swapping the verified bundle. CUA reopened
the supported path and regained window access. All four saved Harness tabs
restored, including the renamed empty page. File labels, solid Open Agent,
New / Local / Remote folders, one-row machine choices and Machines agent counts
and submenus were inspected without creating, stopping or typing into an agent.
The previous bundle remains at
`desktop/build/macos/Build/Products/Release/.harness-before-labels-k3lw36qc/Harness.app`
and the verified backup is
`/private/tmp/harness-before-agent-entry-ldyjh3ru/Harness.app`.
`/private/tmp/harness-agent-preview-install.json` records the install.

**Quit Harness (Cmd-Q) is the correct graceful quit command.** The prior request
for “Quit and Keep Windows” was incorrect; that item does not exist in this app.
The installed build already flushes pending tab layout on normal quit, and agent
sessions run separately. Saved layout is in `desktop-app-v2/state.json` under the
Harness data directory; do not dump its contents. Check the exact app process is
gone immediately before swapping the verified bundle, and do not launch the
derived-data copy alongside the supported one.

CUA-sent Command-N remains inconclusive, although native callback, exported
shortcut and Flutter interaction checks pass. Window access returned for c0fd824 and its panel was inspected via the titlebar
action, but window access is unavailable again for the 8873f27 update. The automation result alone does not justify changing
keyboard dispatch.

Use [the detailed entry/pane contract](harness-agent-first-tabs.md) when editing
or validating UI. The decisions that previously conflicted with older handoffs
are:

- **Add Agent unifies search and creation.** A single titlebar button and
  File → Add Agent… open results and preview immediately, with the search
  field focused, Open Agent below results and the compact creation row anchored
  beneath. This supersedes compact-first modal entry and separate creation;
  the New Harness page stays compact until activated. Creation preserves split
  placement. The bell stays beside the traffic lights.
- **Cmd-T: New Harness; Cmd-N: Add Agent; Shift-Cmd-N: focus creation; Cmd-S: Layout.**
  Cmd-O is unbound by default.
  Cmd-H/J/K/L and Cmd-arrows focus panes; Cmd-1…9 select tabs. User bindings take
  precedence. Cmd-R splits right and Cmd-D splits down. Native menus, help and actual
  dispatch must agree; native menu and titlebar hover hints are removed.
- New Harness preserves incoming **fea77a8**: an Aurora mesh background in the
  app/accent/agent colours and a glass product strip with the device cutout.
  The long search field is capped at 1120 logical pixels with a 64-pixel minimum
  height and **Find an agent** hint. It starts blank and focused, with results
  hidden until typing, clicking or pressing an arrow. Open Agent and New Agent
  sit underneath at the same left edge; the Open button is outlined here.
  Search retains its position and width; results and preview are side by side
  from 700 pixels. Escape restores the actions and query. The product strip stays
  32 pixels above the bottom while search opens and closes, with a compact form
  for short windows. The old lake screenshot is no longer the current background.
- Search is single-choice. Session names appear above **project · branch ·
  machine**, without repeated workspace titles. Only the highlighted row shows
  **Open Agent / Open N Agents**, or the explicit split action. The modal
  has a 90% black backdrop. Open Agent remains beneath results and the New agent
  creation row stays below; there is no Commands footer or “or” divider.
  Commands remain available through Shift-Cmd-P or typing **>**.
- Both search entry points show existing session excerpts. Working sessions lead
  with the observed request and activity; idle sessions show an existing response.
  Pending questions are prominent and group previews put waiting agents first.
  No model calls or generated summaries: only `agent_recent` and ordinary live
  events. No `session_get`, full-history read, or terminal attachment. Cached
  selection is immediate; cold data fills asynchronously. Disconnected records
  retain saved text without claiming a live working/waiting state.
  Query words also match those cached excerpts without additional reads; names
  and metadata rank first. Live matches retain selection and stable row order.
  Page Up/Down scrolls preview content without changing selection or typing focus;
  both actions participate in the configurable Search keymap.
- The Harness application menu includes **Check for Updates…**, using the
  existing manual update-check dialog, directly above Flash Firmware.
- The combined panel uses **New Agent** for the creation heading and **Create**
  for its action. Agent, Project and Machine dropdowns show selected defaults;
  keyboard input stays with the active menu or field. Options contains account
  and permission settings. Escape or one outside click dismisses the panel;
  an in-progress launch cannot be dismissed accidentally. An uncertain outcome
  retains Close and Check status and the original receipt, never starting twice.
  Search/destination controls are blocked during launch or uncertainty.
  Opening a local/remote folder chooser preserves the mounted form and selections.
  Creation success focuses the newly created pane instead of the old terminal.
  The standalone direct-choice form remains for non-workspace entry points.
- A single-agent tab/search/history entry uses that agent's engine icon;
  multiple agents use four outlined tiles. An empty tab uses a plain plus, and
  tab close marks appear only on hover/focus. Only one unused New Harness page
  is allowed; all New Harness actions reuse and focus it, including at the tab limit.
  Restore collapses old duplicate unused pages. Blank pages are excluded
  from Recently Closed. File uses Rename Harness / Close Harness, then pane actions;
  Rename has a clean unlabeled field and muted pill actions. Double-clicks are
  contained within the native tab, and modal appearance leaves the titlebar
  button colors intact while blocking their actions.
  Pin/Unpin and Add Project are absent. Machines follows Models and starts with
  **Open Machines Manager**, with visible Rename actions.
- Pane headers show agent icon/session on the left and folder/branch/machine
  on the right, with a small muted branch glyph before the branch. Header hover
  or keyboard focus reveals **Zoom Pane, Restart Agent, Stop Agent, Close Pane**, with
  Keyboard first for remote sessions. Stop uses a plain filled square and a clear
  confirmation; the existing action ends the process and removes its active
  entry, preserving project files and saved conversation history. Divider grips appear on
  hover/focus/drag. Right/bottom edge plus controls retain explicit split
  placement and remain hidden while zoomed or dragging.
- New, restored, reopened, reconnected, revisited, resized, relaid-out and
  zoomed panes show the latest output. Manual scrollback in an unchanged pane
  and the selected result in an active Find remain usable.

## Current source and verification

Recent pushed checkpoints:

| Checkpoint | Change |
| --- | --- |
| **021ef72** | Makes the New Tab search field taller (64-pixel minimum), keeping the fixed field geometry and footer through preview expansion. |
| **620a868** | Visible machine and agent choices, selected overflow option in the third slot, clearer selection and preserved folder on repeated selection. |
| **526b832** | Restores the original lake wallpaper and pins the device near the fold with the single Meet the Harness device caption. Search uses the remaining space without moving the footer. |
| **1dd7c4b** | Long fixed-width search with the Find a harness hint; restores the mesh wallpaper and aligns smaller actions and the device card left, removing the large heading. |
| **f5d293c** | Restores Check for Updates in the Harness menu. |
| **90b6f68** | Page Up/Down reads preview content without moving search selection or focus; bindings support remapping, repeats and composition guards. |
| **2292fe8** | Cached commit receipts show their existing outcome paragraphs, keeping useful earlier context visible. |
| **08f4c98** | Retain earlier existing responses so an acknowledgement or commit receipt does not hide the session's purpose. |
| **76bdf6e** | Disconnected previews retain text with honest state; all preview and existing desktop checks verified together. |
| **91cfb6a** | Shared responsive previews in Cmd-O and inline search, waiting-first groups, retained keyboard ownership and visible actions after expansion. |
| **7da0c12** | Bounded existing-content cache, two background reads at a time, independent request/response records, stale-session guards and live event isolation. |
| **300f04d** | Every New Tab entry reuses the existing unused page, including at capacity. Restore collapses old duplicates without changing named or populated tabs. Rebases cleanly on 051ea5b, the separate link-prompt revisit fix. |
| **804eb93** | Clearer cropped official device image, hand cursors, pill buttons and transparent outlined Open buttons; consistent native/pane zoom and close icons; Rename Tab and Close Tab wording. |
| **518977c** | Roomier unified titlebar, hover-only tab close marks, minimal plus/group/branch icons, split shortcuts, and unique useful layout choices through the supported pane limit. |
| **f25e5a2** and preceding input checkpoints | Readable large-text entry choices, visible selected results after resize, retained renderer/input ownership, and immediate navigation/Find transitions. |

The current preview uses existing session data only. A read-only local audit
found useful requests and full saved answers in several Codex sessions, and no
meaningful text in one Claude session. It does not invent missing content or
promise complete coverage for every engine. The protocol is unchanged.

The visible-choice refinement has **91 passing desktop tests** in
/private/tmp/harness-visible-choices-tests.log. Coverage includes overflow
selection and replacement, quick switching, immediate menu typeahead, keyboard
focus, selected-machine idempotence, machine/folder races, remote folders, Codex
profiles, large-text layouts and creation recovery. Changed Dart files analyze
cleanly in /private/tmp/harness-visible-choices-analyze.log.

The taller search field passes **42 existing entry/search checks** in
/private/tmp/harness-taller-search-tests.log, with clean analysis in
/private/tmp/harness-taller-search-analyze.log. Real-font renders are in
/private/tmp/harness-taller-search-captures. Field alignment, keyboard behavior
and the pinned device remain covered at normal, narrow and large-text sizes.

The preceding lake/footer pass has **32 passing entry/search tests** in
/private/tmp/harness-lake-entry-tests.log and a clean analysis in
/private/tmp/harness-lake-entry-analyze.log. They verify fixed field geometry and
the device's identical bounds before and after search, including short windows.
The earlier **131-test** entry/search run in
/private/tmp/harness-wallpaper-entry-tests.log also covered preview paging,
composition, retained focus, bootstrap and first use; it predates the latest
lake and choice refinements.

The exported keyboard bindings pass **93 native keymap checks** and **388 AppKit
checks**, including hidden window layout, in
/private/tmp/harness-preview-keyboard-native.log. Native latency benchmarking
remains deferred. The earlier complete suite passed **1,562 desktop tests**, with
one optional media placeholder skipped, in
/private/tmp/harness-preview-context-verified.log; that full run predates the latest
entry and installer changes.

The creation form was rendered with real fonts at 900×720, 880×560 and
600×700 with 200% text in /private/tmp/harness-visible-choices-captures. The
normal-size rows keep all three choices and **…** together; larger text wraps
without clipping names. Captures include a selected fourth machine and Kilo in
the third agent slot. These renders use synthetic data and do not launch agents.

The lake start page was rendered at normal, narrow and larger-text sizes in
/private/tmp/harness-lake-entry-captures. The installed **526b832** build was
inspected directly and the user approved its background, preview and footer
placement. The restored native Check for Updates command was verified earlier:
it opened the existing update offer; no update was installed.

### September 15 unified entry checkpoint

- **8ada851**: clean Rename Tab; consume native tab mouse-up so rename cannot
  trigger window zoom; preserve titlebar action colors behind a modal.
- **44148d7**: search existing cached session excerpts without extra reads.
  Stop uses the standard filled square; incoming managed tmux work is retained.
- **9af924f**: compact Add Harness chooser on Cmd-N; one titlebar/File entry;
  New Tab label and legacy-name restoration; visible creation for both splits.
- 355 affected Flutter checks are covered by the broad run and the focused
  rerun of corrected expectations. Logs: /private/tmp/harness-unified-entry-regressions.log
  and /private/tmp/harness-unified-entry-final-tests.log. The latter passes all 21.
  Three real-font picker checks pass at 1280, 760 and 600 pixels, including 2×
  text: /private/tmp/harness-picker-render-tests.log. Captures are in
  /private/tmp/harness-picker-entry-captures. The editor retains exact geometry;
  Enter on the focused New button opens creation rather than the selected result.
- Native AppKit: 374 checks pass, including hidden-window geometry, tab click
  isolation, menu/shortcut agreement and identical action colors under a modal.
  Log: /private/tmp/harness-unified-entry-native.log. No benchmark ran.
- Changed Dart analysis is clean after removing one unused test import.

### Prepared build versus running preview

Prepared build location:

/private/tmp/harness-pane-controls-release/Build/Products/Release/Harness.app

Only supported current preview location:

/Users/ab/code/autonomous-harness/desktop/build/macos/Build/Products/Release/Harness.app

Historical **9af924f** installation receipt (superseded by the checkpoint above): Release succeeded in
/private/tmp/harness-unified-entry-release.log. Both bundles passed deep, strict
signature verification. Installation used a graceful quit, an exact
stopped-process check before and immediately before the swap, and a verified
staging bundle. The previous live bundle is backed up at
/private/tmp/harness-before-unified-entry-wyqay10k/Harness.app.

Live verification confirmed the existing app v2 (three panes), workshop and
personal tabs restored, together with the existing empty page now named New Tab.
The titlebar and File menu each expose one Add Harness action. Both open the
compact chooser; its New button opens the direct-choice creation form. Native
tab double-click opened the cleaned-up Rename Tab without changing window size,
and Add Harness retained its normal colors behind the modal. Rename and creation
were dismissed without changing names or launching a session. The taller lake
start page and fixed device footer were inspected, and New Tab was left selected
for review. CUA's synthetic Command-modifier attempts had no observable effect
for either Cmd-N or the unchanged Cmd-T; shortcut dispatch is covered by the
Flutter and isolated native checks, not claimed as a live CUA keyboard result.

Before installing later changes, verify the new Release build and signatures,
use **Quit Harness (Cmd-Q)**, then check the exact process is stopped. Normal
quit flushes saved layout; it does not stop the independently running agents.
Back up and replace only the current checkout's bundle, verify it, and reopen
that exact path. Do not call getApp between quitting and copying, since that
lookup can relaunch the app. Live CUA access must be checked again after launch.

The older pre-lake preview backup remains at
/private/tmp/harness-before-lake-entry-fmqz73k5/Harness.app.
Do not open the other checkout's retired UI or /Applications/Harness.app. Do not
restart/upgrade the user's CLI daemon or type test commands into working agents.
Temporary logs, SDKs, builds, account state and preview processes do not transfer
with Git.

## Creation and preview work

The approved visible-choice refinement is implemented in **620a868**. This removes
the primary machine dropdown and the detached selected-agent line. It preserves
engine discovery, profile checks, folder targeting and uncertain-launch recovery.

The **New / Local / Remote project-folder workflow is now implemented**; see the
continuation checkpoint above and [creation recovery](harness-agent-creation.md).
It preserves remembered agents, selected-machine targeting and the original split.
Do not infer a project from the current pane in a multiproject workspace.

Command-held tab number hints were discussed as a discoverability improvement:
brief hold, subtle hints in each tab's right edge, no label movement. They have
not been implemented.

Continuing the lake wallpaper into the native selected New Tab was inspected
and deliberately left out under the user's “only if simple” constraint. The
AppKit accessory is outside the Flutter content view; a seamless image would
need coordinated cropping and positioning across resize/fullscreen. No native
tab background or window content layout was changed for this idea.

The user approved **building a useful, beautiful, fast search preview** in Cmd-O
and New Tab. The shared UI and cache are now implemented. The user explicitly
forbids generating new summaries: display available data only. The
[preview design](harness-search-preview.md) records the implementation and
coverage limits. The [Rex study](mitchellh-rex-study.md) is saved, pushed,
and open for the user in Chrome. The following audit remains relevant:
The old implementation at f04f6d3 read only already-attached terminal buffers,
showed at most twelve nonblank tail lines, provided no group preview, and froze
the snapshot while the selection stayed put. Terminal prompts/tool noise rarely
answered which task this was or what happened. The failure was content selection
and availability, not simply insufficient preview width.

The app owns a separate bounded session-excerpt cache; Agent metadata itself
still has no prompt/reply fields. CLI normalization yields user messages and replies.
`session_get` can return small windows but still read the entire transcript,
so it is intentionally excluded from the preview. `agent_recent` exposes
asks and recaps, but recaps can be device-gated and absent. Do not treat nth ask
and nth recap as paired turns or assume coverage for every engine/remote daemon.

The preview shows existing requests, responses and waiting questions with
project/branch/machine context. Groups render visible members, waiting first.
The live check found commit receipts hiding useful older explanations, so the
preview now retains and displays the existing earlier response excerpts too.
The latest and earlier answers remain separately labeled; none are generated.
Bounded records update as events arrive and render from memory on highlight.
Background refresh discards stale session replies. A settled cold selection may
schedule the lightweight cache read; no arrow waits for it. Fresh uncached remote
content cannot have literal zero latency. More engine/remote coverage remains
useful; missing content must remain explicit.

The three Rex posts and demo visuals/full captions have been reviewed, with no
post-inspired implementation:

- [CLI automation](https://x.com/mitchellh/status/2099622049325232505): named sessions,
  layout manipulation without process restarts, process wait/exit status, events,
  and capture/input APIs. Potential lesson: one coherent human/agent workspace
  model with structured events. Process exit alone does not mean an AI task is done.
- [Appearance](https://x.com/mitchellh/status/2097449191325028407), including the
  [quoted demo](https://x.com/almonk/status/2097439320076403125): coordinated app
  themes and comfortable/compact pane density. Potential lesson: hierarchy,
  spacing and whole-app surfaces matter more than isolated rounded controls.
- [Remote continuity](https://x.com/mitchellh/status/2097424868203758046): persistent
  remote sessions and the same directory navigation in local/remote work.
  Potential lesson: preserve place and interaction habits while keeping machine
  identity clear. The demo is not a measurement of Harness latency.

## Runtime and recovery invariants

- A swarm is a named collection of views with deliberate membership. Discovery
  never silently adds/removes members. Opening an existing agent reuses its
  session/buffer/controller and leaves source workspaces intact.
- Each workspace retains arrangement and focus. Closing views or tabs preserves
  runtimes; navigation never sends terminal input or takes over another controller.
  Stop Agent continues to use its explicit confirmation; files and saved
  conversations are preserved, but the live process ends.
- Reopening one agent and then its original swarm reuses that workspace and adds
  missing views, retaining newer names, layout, focus and retained sessions. If
  all missing views cannot fit, preserve the closure; do not partially restore,
  evict other views or duplicate the workspace.
- Search, navigation and History honor the chosen/captured destination.
  Asynchronous folder/creation/split results revalidate it. A closed workspace,
  changed neighbor, capacity limit or stale membership cannot redirect a result
  silently or lose the user's choices.
- Preserve drafts, selection, paste, composition and the next keystroke's target
  across transitions. Output and background discovery cannot steal input focus.
  Hidden terminals keep their renderer without unnecessary layout/paint.
- Remote folder browsing has editable paths, keyboard navigation, retry and
  latest-request ownership. A failed or pending hop cannot select the previous
  folder. Late replies cannot replace a newer draft or composition.
- [Creation recovery](harness-agent-creation.md) distinguishes refused creation
  from a delayed/lost response. **Check status reads the original receipt; it
  never submits another launch.** A confirmed runtime returns to its validated
  destination or remains discoverable in Open Agent. Older CLIs can create
  without supporting receipt recovery. Intents last only for the open dialog;
  durable pending-creation and crash-window reconciliation remain future work.
- Browser sign-in supports reopen/copy/cancel with stale-attempt isolation.
  Cloning preserves URL/destination and visibly cleans up cancellation. Bootstrap
  installation keeps actions visible, exposes optional details, and supports
  keyboard retry/read-only rechecks. These recovery paths are implemented and
  fixture-checked; real first use remains unobserved.
- The [Archive/Resume lifecycle document](harness-agent-lifecycle.md) is a
  proposal, not implemented behavior or permission to archive/delete user agents.
  [Shared-swarm collaboration](harness-collaboration-design.md) is also a
  separate proposal/prototype, not implemented multiplayer.
- Models/accounts remain available. Ordinary shells, a full IDE, permanent
  management sidebars and unrelated dashboards remain outside this desktop pass.
  Notifications reflect real pending questions; no sample agents/statuses belong
  in the normal application.

## Next-work order

1. **Continue current main and preserve the current product direction.** Inspect
   local changes before a fast-forward update. Save verified work frequently.
   Update only the correct preview using the process above. Do not reopen old UI or repeat unchanged menu checks merely to fill a
   verification gap.
2. **Complete current keyboard and genuine first-use qualification.** Check
   initially focused search with hidden results, expansion/dismissal, command mode, Tab-focused
   rows, composition and the first key after activation through both native
   menu and keyboard entry. Check New Agent folder focus/cancellation,
   Layout repeated chords and confirmation, and Find during output/composition,
   including the immediate next key after closing it. Ready navigation, Find
   and dialog-return transitions are now fixture-checked before their next
   frame; current-preview observation remains the next level of evidence.
   Observe fresh dependencies, provider sign-in/browser return, native folder
   choice, clone, first task and a second agent. Record actual steps, errors
   and time to a usable agent. Public GitHub cloning passed a direct disposable
   service check; private access/native chooser and real provider return remain
   unobserved. Check delayed remote creation on a disposable agent, an older CLI
   and a changed original destination without submitting duplicate launches.
3. **Recheck terminal positioning and real workflows on disposable local/remote
   sessions.** Cover startup, delayed snapshots, incremental resize, added panes,
   retained views, zoom, relayout, return, reconnect, paste, selection and IME.
   Preserve deliberate unchanged scrollback/Find and verify the next input target.
   Do not type test commands into the user's working agents or upgrade/restart
   their daemon for qualification.
4. **Keep native latency measurement deferred.** If the user restores it to
   scope, rebuild a disposable fixture from current source and require the
   active/key-window guards to pass. Measure cold/warm p50/p95/p99 for typing,
   pane focus and tab changes with 16/48 retained terminals, idle and under
   output load. Record machine, build, raw samples and limits. Do not substitute
   headless search CPU, raster-only time or network RTT for native latency.
   Separately finish native visual/accessibility and Linux-host qualification;
   macOS checks do not establish Windows support.

## Acceptance criteria

### Entry, navigation and input

- A first-time developer can identify the next action without learning the
  machine/project/swarm/account model first. New and Open stay distinct, the
  happy path requires few meaningful choices, and failure offers a useful next
  step without losing selections.
- Current keyboard defaults, user overrides, native actions and shortcut help
  agree. Search input/results keep one selection and action, including arrows,
  Enter, Escape, select-all/delete, paste and composition.
- The first character after navigation reaches only the selected agent. Hidden,
  offscreen or zoomed destinations are revealed with retained sessions intact.
  Discovery/output cannot steal focus or reconstruct dismissed search catalogs.
- Opening existing work starts no duplicate runtime. Splits preserve their
  exact destination. Already-present, offline, removed, full, changed, canceled
  or failed actions give a clear result and never alter the wrong workspace.
- Partial History restoration retains a single workspace/shared sessions, even
  at the tab limit. Capacity failure preserves the whole recovery entry.
- Closing/dismissing New Agent returns directly to the intended page/terminal;
  launch-in-progress and uncertain-outcome recovery remain protected.

### Visual quality and first impression

- The start page, titlebar, modal result rows and pane controls follow the current
  entry/pane contract. The start-page lake, whitespace, title/metadata hierarchy,
  single/group icons, labels and native/Flutter button contrast are consistent.
- All six coordinated palettes, real fonts/content, larger text, narrow windows,
  keyboard focus indicators and accessibility labels remain legible and usable.
  Modal hierarchy, grips, splits, zoom, menus and account rows look intentional.
- Observe real first-use completion/confusion. The user's aspiration to hook
  everyone instantly is not measured 100% conversion. Fixture success is not
  evidence of fresh-install completion.

### Correctness, performance and release

- Fresh/revisited views show the latest output, including tall/delayed snapshots,
  incremental resize redraws and multi-agent transitions. Deliberate unchanged
  scrollback and active Find retain their position.
- Shared agents retain one session/buffer/controller. Hidden output does not
  repeatedly lay out/paint hidden terminals, and routine events do not rebuild
  unrelated workspace UI.
- Reconnect retains readable output/drafts without blindly replaying input or
  taking control from another controller. Real remote evidence is still required.
- Native latency claims require valid foreground measurements with source,
  environment and raw-sample scope stated; benchmarking is currently deferred.
- Run meaningful affected checks and analysis; run native decoder/titlebar
  checks when native behavior changes. Build Release before updating the preview
  and verify the running artifact before claiming it loaded the change.
  Passing a full desktop suite is required before declaring release readiness,
  but it does not replace native/macOS, Linux-host or first-use qualification.

## Implementation map and references

| Area | Start here |
| --- | --- |
| Workspace routes, native callbacks, split/creation context | desktop/lib/screens/swarm_screen.dart |
| Start page and shared Open results | desktop/lib/widgets/harness_start_page.dart, swarm_switcher.dart, swarm_search_input.dart |
| Creation and remote folders | desktop/lib/widgets/new_agent_dialog.dart, remote_folder_picker.dart |
| Search/actions/destinations | desktop/lib/state/swarm_search.dart, swarm_navigation.dart, swarm_catalog.dart |
| Native tabs, toolbar, menus and key ownership | desktop/macos/Runner/SwarmTitlebar.swift, HarnessKeymap.swift; desktop/lib/shortcuts/ |
| Membership, retained panes and event routing | desktop/lib/state/app_state.dart, swarm.dart, terminal_pane.dart |
| Terminal viewport, Find and remote snapshots | desktop/lib/widgets/terminal_panel.dart, terminal_find_bar.dart; desktop/lib/terminal/; desktop/third_party/xterm/lib/src/ui/render.dart; cli/src/lib/terminalStreamManager.ts |
| Focused regression coverage | desktop/test/terminal_initial_output_test.dart, terminal_find_test.dart, workspace_event_isolation_test.dart, swarm_terminal_routing_test.dart, keymap_runtime_test.dart |
| Native functional checks | desktop/tool/check_keymap_native.sh, check_swarm_titlebar.sh |

[Keyboard design](harness-v2-keyboard-system.md),
[developer-tool research](harness-v2-developer-tools-research.md),
[performance evidence](harness-v2-performance.md) and
[onboarding history](harness-v2-appearance-onboarding.md) provide background.
Read their proposals/historical measurements in the context of the current
entry contract. Archived handoff patches are superseded; do not reapply them.

## Toolchain and operating boundaries

Read desktop/CLAUDE.md, using current source where its old integration-test,
sidebar or architecture notes differ. No applicable AGENTS.md was found in this
checkout or its ancestors.

This checkpoint used **Flutter 3.47.2 / Dart 3.13.2**, Swift Package Manager and
Xcode on Apple Silicon. The local SDK is /private/tmp/harness-v2-flutter and tool
config is /private/tmp/harness-v2-tool-config. Select a compatible SDK on another
computer; those temporary paths are not portable dependencies. From desktop/:

~~~sh
flutter config --enable-swift-package-manager
flutter pub get
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
bash tool/check_keymap_native.sh /absolute/path/to/flutter-sdk
~~~

Serialize Flutter tooling, including the native script's Dart export and Xcode
build phases. Enable SPM before pub get; do not commit a CocoaPods fallback,
generated output, caches, credentials or real account/terminal state. Vendored
xterm patches are required; do not replace them with the pub.dev package.
The normal entry point is desktop/lib/main.dart. macOS uses
ai.autonomous.harness; Linux uses com.autonomous.harness/executable harness.
Older process identity does not prove which on-disk source it loaded.

Keep tests isolated with temporary stores and synthetic/disposable transports.
Preserve the user's sessions, agent input and production daemon. Commit/push
directly to main with ordinary fast-forward pushes; integrate incoming main
without rewriting published history. Do not merge or retire teammates' branches.
Publishing a release or production end-to-end operations are separate tasks.
Keep this handoff current without appending superseded designs as new instructions.
