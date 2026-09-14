# Harness v2: goal, plan, and continuation handoff

Updated September 14, 2026. Resume on current **main**, preserve local work, and
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
  precedence. Native menus, help, hover hints and actual dispatch must agree.
- New Tab uses the Google-like page with a **solid selected-tab background**,
  lower centered controls and generous whitespace. Search is at most 640 logical
  pixels wide, blank and unfocused initially. Clicking it reveals the same
  results, selection, arrows and Enter behavior as Cmd-O. Open Harness and
  accented **+ New Harness** sit below it; a small official device image and
  introduction sit well below, linking to autonomous.ai/harness-device.
  The five recent-agent rows are removed.
- Search is single-choice. Session names appear above **project · branch ·
  machine**, without repeated workspace titles. Only the highlighted row shows
  **Open Harness / Open N Harnesses**, or the explicit split action. The modal
  has a 90% black backdrop and no Commands footer, creation CTA or “or” divider.
  Commands remain available through Shift-Cmd-P or typing **>**.
- Creation uses **New Harness** for its title and CTA, with no ordinary Cancel.
  Escape or one outside click dismisses it directly. A pending launch cannot be
  dismissed accidentally; an uncertain outcome retains Close and Check status.
  The form does not restore search underneath it.
- A single-agent tab/search/history entry uses that agent's engine icon;
  multiple agents use the group icon. Unused default-name blank pages are excluded
  from Recently Closed. File groups harness/tab actions, then pane actions;
  Pin/Unpin and Add Project are absent. Machines follows Models and starts with
  **Open Machines Manager**, with visible Rename actions.
- Pane headers show agent icon/session on the left and folder/branch/machine
  on the right. Header hover or keyboard focus reveals muted **Zoom, Delete,
  Close**, with Keyboard first for remote sessions. Divider grips appear on
  hover/focus/drag. Right/bottom edge plus controls retain explicit split
  placement and remain hidden while zoomed or dragging.
- New, restored, reopened, reconnected, revisited, resized, relaid-out and
  zoomed panes show the latest output. Manual scrollback in an unchanged pane
  and the selected result in an active Find remain usable.

## Current source and verification

**8d754db** restores keyboard/text input immediately when Find closes and is
pushed to main. All affected checks, analysis and full desktop regressions pass.
The prepared, verified Release now includes this change; the running preview
remains unchanged while the console is locked.

| Checkpoint | Verified change |
| --- | --- |
| **8d754db** — Find dismissal | Escape or the close button previously lost an arrow key and text arriving before the next frame. Dismissal now immediately restores the retained terminal's input connection, or the visible composer's field and draft. The renderer and remembered Find query stay intact. |
| **8b73106** — terminal Find | Ten output updates now rebuild the editor zero times instead of ten. Results update around it while match, caret, composition and focus remain stable. Enter/keypad Enter and Escape return to the platform input method during composition; normal navigation/dismissal resumes afterward. |
| **99d1ac9** — workspace events | Routine heartbeats and dial scrolling no longer rebuild the workspace or visit unrelated retained terminal JSON handlers. Busy-state transitions, watchdog expiry, dial status, hidden ready replies and machine transport failures retain their routing. |
| **d5756ab** — Layout | Repeating the configured Layout chord cycles choices; modified digits/arrows cannot accidentally apply a shape. Highlighting preserves geometry. Large text gets readable, scrollable choices and navigation follows actual wrapped rows. Confirmation retains the agent and latest output. |
| **0c240dd**, **a64ab4e** — picker focus | Input and Tab-focused result rows share shortcut ownership. Native New Harness and command actions use the focused picker, close it before creation, and wait for destination focus. Remapped/unbound keys and composition remain respected. |
| **67c20f4**, **581d0a4**, **b26424e**, **98fc760** — current entry/creation | Current New/Open fixtures replace retired UI expectations. Native/Flutter button styling agrees. Initial folder focus, chooser retry, account lookup, one-step dismissal and original creation destination are covered. |
| **87706a3**, **2aaa48a** — inline search | Command entry synchronizes the field and results; dismissed pages retain no search subscription/catalog work. Reopening refreshes against current state without rebuilding the editor on every arrow selection. |
| **b4baf68**, **e8960fc**, **9288ea4** — live preview baseline | Separate New/Open, the current start page/device image/dialog copy, readable titlebar controls and the incremental Codex resize scrolling fix were built and checked in the correct preview. |

Current checks:

- **1,438 desktop unit/widget checks pass**, with one optional CLI-media
  placeholder skipped. Log: /private/tmp/harness-find-focus-full.log.
- All **70 affected Find/focus/composer/viewport/keymap checks pass**. Both
  changed files analyze cleanly. Logs: /private/tmp/harness-find-focus-checks.log
  and /private/tmp/harness-find-focus-analyze.log. The two before-fix terminal
  failures are in /private/tmp/harness-find-focus-before.log.
- The current exported Dart bindings pass **84 native keyboard checks** and
  **363 AppKit titlebar checks**, including hidden native window layout.
  Log: /private/tmp/harness-current-native-contract.log. The script completed;
  it displayed no windows and opened no agents.
- The normal arm64 **Release build succeeds** through 8d754db. Both rebuilt
  frameworks verified before refreshing the outer ad-hoc signature; the full
  bundle passed deep, strict signature verification.
  Build log: /private/tmp/harness-find-focus-release.log.
- Four optional CLI-media checks previously passed at 67c20f4 in
  /private/tmp/harness-current-media-smoke.log. They use isolated identities,
  synthetic media, loopback transport and a stubbed OS launch boundary.

These are functional checks, isolated renders and deterministic work counts.
They do not establish live native IME behavior, real remote reconnect, first-use
conversion or native event-to-display latency. The
[performance record](harness-v2-performance.md) keeps measurement scopes and
earlier counts separate.

### Prepared build versus running preview

**Prepared, verified Release through 8d754db:**

/private/tmp/harness-pane-controls-release/Build/Products/Release/Harness.app

**Running preview, still the b4baf68 baseline:**

/Users/ab/code/autonomous-harness/desktop/build/macos/Build/Products/Release/Harness.app

The newer bundle has **not** replaced the running preview. The exact preview
process was confirmed as PID 92821 during this checkpoint; recheck before acting.
The console still reports **CGSSessionScreenIsLocked = Yes**. Earlier exact-path
app-control lookups returned cgWindowNotFound despite the process running.
A lookup failure is not evidence that an app stopped.

Only update the current checkout's preview. The user paused the other checkout;
do not open its retired UI, another fixture, or /Applications/Harness.app.
Do not overwrite a running app bundle while the console is locked. When the
console is accessible, use **Quit and Keep Windows**, verify the exact process
has stopped, back up the preview, copy the verified bundle, verify it, and reopen
that exact path. Ordinary Quit can terminate agents. After quitting, a fresh
app-control lookup can relaunch the app; use the process check before replacing
the bundle. A prior backup exists at
/private/tmp/harness-before-final-entry-0bmbrwl5/Harness.app.

Live checks apply only to the baseline preview: both idle workshop Codex panes
held their latest message/prompt across repeated rows/columns changes and delayed
repaint. The app v2 Codex/Claude workspace also held its bottom after restoring
columns. Both workspaces were returned to their original columns. The current
start-page colors/spacing/device image, absent initial caret, click-to-search,
filtering, arrow selection, New Harness title/CTA, absent Cancel and single
outside-click dismissal were verified there. No real agent received test input.

Temporary logs, SDKs, builds, account state and preview processes do not transfer
to another computer with Git.

## Runtime and recovery invariants

- A swarm is a named collection of views with deliberate membership. Discovery
  never silently adds/removes members. Opening an existing agent reuses its
  session/buffer/controller and leaves source workspaces intact.
- Each workspace retains arrangement and focus. Closing views or tabs preserves
  runtimes; navigation never sends terminal input or takes over another controller.
  Delete continues to use its explicit confirmation.
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
   When native access returns, update only the correct preview using the process
   above. Do not reopen old UI or repeat unchanged menu checks merely to fill a
   verification gap.
2. **Complete current keyboard and genuine first-use qualification.** Check
   initially unfocused search, expansion/dismissal, command mode, Tab-focused
   rows, composition and the first key after activation through both native
   menu and keyboard entry. Check New Harness folder focus/cancellation,
   Layout repeated chords and confirmation, and Find during output/composition,
   including the immediate next key after closing it.
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
  entry/pane contract. Flat backgrounds, whitespace, title/metadata hierarchy,
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
