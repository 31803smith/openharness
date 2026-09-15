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
a swarm. The user describes it as a “super terminal” for the intelligence age.
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

Use [the detailed entry/pane contract](harness-agent-first-tabs.md) when editing
or validating UI. The decisions that previously conflicted with older handoffs
are:

- **New Harness creates; Open Harness finds existing work.** They are explicit
  titlebar buttons with separate popups. The bell is beside the traffic lights.
  The floating bottom-right plus is removed.
- **Cmd-T: New Tab; Cmd-N: New Harness; Cmd-O: Open Harness; Cmd-S: Layout.**
  Cmd-H/J/K/L and Cmd-arrows focus panes; Cmd-1…9 select tabs. User bindings take
  precedence. Cmd-R splits right and Cmd-D splits down. Native menus, help and actual
  dispatch must agree; native menu and titlebar hover hints are removed.
- New Tab uses the **restored lake-at-dusk wallpaper**, a long search field capped
  at 1120 logical pixels, and no large Harness heading. The hint is **Find a
  harness**. Search starts blank and focused, with results hidden. Open Harness
  and New Harness sit underneath, aligned with the search field's left edge.
  Search has a **64-pixel minimum height** with more vertical padding; the
  action buttons remain 48 pixels high. Cmd-O retains its existing input size.
  Activating search preserves the field position and width; results and preview
  appear side by side from 700 pixels wide, and the actions hide. The buttons
  wrap when needed. Escape restores the actions and query.
  Typing, clicking, or pressing an arrow
  reveals the same results, selection, arrows and Enter behavior as Cmd-O.
  Focus alone leaves results hidden and builds no catalog. Open Harness and
  accented **+ New Harness** share a row below search; a small official device
  image and **Meet the Harness device** caption stay in a footer 32 pixels above
  the bottom, aligned to the same left edge and linking to autonomous.ai/harness-device.
  Search uses the remaining space above the footer, which stays still when results
  open or close. Short windows use a compact horizontal device card.
  The five recent-agent rows are removed. Both pairs of actions are rounded
  pills, with transparent outlined Open buttons and hand cursors. The official
  `2.webp` device photo is cropped and centered in its viewport, with a hand cursor.
- Search is single-choice. Session names appear above **project · branch ·
  machine**, without repeated workspace titles. Only the highlighted row shows
  **Open Harness / Open N Harnesses**, or the explicit split action. The modal
  has a 90% black backdrop and no Commands footer, creation CTA or “or” divider.
  Commands remain available through Shift-Cmd-P or typing **>**.
- Both search entry points show existing session excerpts. Working sessions lead
  with the observed request and activity; idle sessions show an existing response.
  Pending questions are prominent and group previews put waiting agents first.
  No model calls or generated summaries: only `agent_recent` and ordinary live
  events. No `session_get`, full-history read, or terminal attachment. Cached
  selection is immediate; cold data fills asynchronously. Disconnected records
  retain saved text without claiming a live working/waiting state.
  Page Up/Down scrolls preview content without changing selection or typing focus;
  both actions participate in the configurable Search keymap.
- The Harness application menu includes **Check for Updates…**, using the
  existing manual update-check dialog, directly above Flash Firmware.
- Creation uses **New Harness** for its title and CTA, with no ordinary Cancel.
  Escape or one outside click dismisses it directly. A pending launch cannot be
  dismissed accidentally; an uncertain outcome retains Close and Check status.
  The form does not restore search underneath it. Machine and Agent show up to
  three direct choices and **…** for the rest. An overflow choice replaces the
  third slot and remains available while switching between the first two.
  Selected choices use an accent tint and check, distinct from the focus outline.
  Machine names retain local/remote and offline/link details. Clicking the current
  machine preserves the working folder; large text wraps the buttons.
- A single-agent tab/search/history entry uses that agent's engine icon;
  multiple agents use four outlined tiles. An empty tab uses a plain plus, and
  tab close marks appear only on hover/focus. Only one unused New Harness page
  is allowed; all New Tab actions reuse and focus it, including at the tab limit.
  Restore collapses old duplicate unused pages. Blank pages are excluded
  from Recently Closed. File uses Rename Tab / Close Tab, then pane actions;
  Pin/Unpin and Add Project are absent. Machines follows Models and starts with
  **Open Machines Manager**, with visible Rename actions.
- Pane headers show agent icon/session on the left and folder/branch/machine
  on the right, with a small muted branch glyph before the branch. Header hover
  or keyboard focus reveals **Zoom Pane, Restart Harness, Stop Harness, Close Pane**, with
  Keyboard first for remote sessions. Stop uses a circle-stop icon and a clear
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

### Prepared build versus running preview

Prepared build location:

/private/tmp/harness-pane-controls-release/Build/Products/Release/Harness.app

Only supported current preview location:

/Users/ab/code/autonomous-harness/desktop/build/macos/Build/Products/Release/Harness.app

The prepared build includes **021ef72** and passed in
/private/tmp/harness-taller-search-release.log with deep, strict signature
verification. Its window-preserving installation is pending while the user
finishes an active folder chooser.

The running preview was updated through **526b832** using Quit and Keep Windows. The
Release build passed in /private/tmp/harness-lake-entry-release.log; the
prepared and installed bundles passed deep, strict signature verification. The
existing app v2, workshop and personal tabs restored successfully, along with
the unused New Harness tab. The resting New Tab layout was inspected in this
exact build; shared search interactions are covered by the widget checks above.
The console is accessible; older locked-console notes are obsolete. Before replacing
it with later changes, verify the new Release build
and signatures, use **Quit and Keep Windows**, then check the exact process is
stopped. Back up and replace only the current checkout's bundle, verify it, and
reopen that exact path. Ordinary Quit can terminate agents. Do not call getApp
between quitting and copying, since that lookup can relaunch the app.

The immediately previous preview backup is
/private/tmp/harness-before-lake-entry-fmqz73k5/Harness.app.
Do not open the other checkout's retired UI or /Applications/Harness.app. Do not
restart/upgrade the user's CLI daemon or type test commands into working agents.
Temporary logs, SDKs, builds, account state and preview processes do not transfer
with Git.

## Creation and preview work

The approved visible-choice refinement is implemented in **620a868**. This removes
the primary machine dropdown and the detached selected-agent line. It preserves
engine discovery, profile checks, folder targeting and uncertain-launch recovery.

The **larger project-creation workflow is not implemented**. The discussed
shape is New Project / Existing Folder / Clone Repository, remembered agent,
and compact This Machine / linked-machine choices in a spacious form. A new
project would create its own folder, requiring no picker or typing. Do not infer
the project from the current pane in a multiproject workspace. The visible-choice
refinement is separate from that larger workflow.

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
  Stop Harness continues to use its explicit confirmation; files and saved
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
  destination or remains discoverable in Open Harness. Older CLIs can create
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
   menu and keyboard entry. Check New Harness folder focus/cancellation,
   Layout repeated chords and confirmation, and Find during output/composition,
   including the immediate next key after closing it. Ready navigation, Find
   and dialog-return transitions are now fixture-checked before their next
   frame; current-preview observation remains the next level of evidence.
   Observe fresh dependencies, provider sign-in/browser return, native folder
   choice, clone, first task and a second harness. Record actual steps, errors
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
- Closing/dismissing New Harness returns directly to the intended page/terminal;
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
