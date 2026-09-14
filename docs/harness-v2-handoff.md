# Harness v2: goal, plan, and continuation handoff

Updated September 13, 2026. **Read this first when resuming on another computer.**
This is the current product contract and next-work order. It supersedes conflicting
historical checkpoints in [the progress log](harness-v2-progress.md). The user
requested a portable checkpoint, then asked this session to resume building;
the overall goal is still active and unfinished.

## Goal

Build the best everyday workspace for people directing persistent AI agents:
a fast, polished, keyboard-first **agentic browser**, with each tab representing
a swarm. The user describes it as a “super terminal” for the intelligence age.
Developers should feel the speed, predictability, and familiar habits of a great
terminal/editor while working with several agents across real machines and
projects. They should keep their place and know exactly which agent receives
their next instruction.

The product is called **Harness**. “V2” is the internal UI/UX project name.
This is a working desktop preview, not a completed release. Improving first use,
navigation, input correctness, and latency matters more than adding many surfaces.
The user wants autonomous progress, frequent commits/pushes, and decisions made
in users' interests. Continue research into strong developer tools after the
concrete issues are handled, adapting their useful habits to directing agents.
Research must lead to justified improvements, not feature accumulation.

## Repository and checkpoint

- Repository: <https://github.com/autonomous-ai/autonomous-harness>.
- Continue on **`app-v2`**, tracking `origin/app-v2`.
- Draft [PR #31 — Harness: swarm workspaces for AI agents](https://github.com/autonomous-ai/autonomous-harness/pull/31)
  is open from `app-v2` to `main`; verified at this handoff. Keep it draft while
  qualification remains incomplete.
- Previous UI checkpoint: `ac443eb`, following `2e8d69d` (search/menu controls),
  `4154cf6` (Harness branding/account labels), and `06ba77c` (agent creation).
- Previous code checkpoint: **`26a372e`**, terminal viewport preservation and naming
  an empty default swarm after its first agent.
- `744c1fe` saved the portable handoff, pending UI drafts, native benchmark
  tooling, and collaboration design notes.
- **`2d3c024`** implements distinct Navigate/Add experiences,
  consistent empty-swarm starters, command-mode focus preservation, and the
  navigation catalog performance improvement described below.
- The user explicitly authorized pushing everything to this public repository
  on `app-v2`; do not ask again for routine checkpoint pushes there.
- After the PR is merged, delete its branch, update `main`, and create a fresh
  branch for the next change. Do not delete `app-v2` while its draft PR is active.

Start with a clean checkout of the remote branch and inspect its latest commit.
On an existing checkout, preserve local work before updating; use a fast-forward
pull, not a reset. The prior computer's `/private/tmp` files, installed apps,
saved account state, and localhost prototype server will not transfer with Git.
The [handoff archive](handoff/app-v2-2026-09-13/README.md) preserves older drafts;
both patches are now superseded by production source. Do not reapply them.

## Core product rules

- A **swarm** is a named collection of agent views. Its membership is deliberate;
  opening a machine/project can seed it once, but later discovery must not
  silently add or remove members.
- An **agent** is a persistent runtime, not necessarily a coding agent. Codex,
  Claude Code, Cursor, Hermes, OpenClaw, and others must fit the terminology.
  Use the label **Agent**, not “Coding agent.”
- One agent can appear in multiple personal swarms. Reuse its session, terminal
  buffer, and retained renderer. Preserve each swarm's arrangement and focus.
- Closing an agent view or swarm tab removes views; it must not stop or delete
  the underlying agent. Focus/navigation must not send terminal input or seize
  control of a runtime controlled elsewhere.
- Keep native macOS tabs and traffic lights, compact pane headers, and a quiet
  canvas. Wallpaper belongs on the empty New swarm page. Existing palettes
  coordinate native chrome, Flutter UI, and terminal colors.
- Preserve text drafts, selection, deliberate scroll position, clipboard/IME
  behavior, and the destination of the first keystroke after every transition.
- Notifications reflect real pending questions. No sample statuses or mock
  agents in the normal application.
- Ordinary shells, a full IDE, permanent management sidebars, and unrelated
  dashboards are outside the current desktop task. Models/account usage remains
  part of the native menu; older notes saying “No Models” are obsolete.

## Latest approved design: two different experiences

This design is now implemented in source. The user explicitly rejected using
one global picker with only different labels/icons for navigation versus adding.
Share data/search utilities where useful, but build **distinct UI and interaction
flows** for these two jobs.

| Entry point | Job | Required behavior |
| --- | --- | --- |
| Top-right navigation icon, replacing Search; Cmd-P | Navigate globally | Find agents/swarms and choose an exact existing destination. |
| New swarm page | Add to this swarm | Find an existing agent or create a new one in this tab. |
| Bottom-right floating + inside the swarm | Add to this swarm | The same Add agent experience as New swarm. |
| Pane menu: Split right / Split down | Add at this position | The same Add agent experience, preserving the selected neighbor and direction. |
| New agent action, including Cmd-N | Create | Always create a fresh runtime in the intended swarm/position. |
| Tab-strip + | New swarm | Create a new swarm tab. |

### Navigate

- Put a navigation icon at the top right, alongside the notification bell.
  Remove the separate top-right New agent +. The implemented glyph is a compass,
  with a Navigate tooltip and accessibility label.
- Make the surface visibly about **places to go**, distinct from Add agent's
  existing-agent search and creation surface. The implemented compact directory
  groups exact agent locations under their swarm names; it has no output preview.
- **If one matching agent appears in three swarms, show all three swarm
  destinations and let the user choose.** Do not silently choose its latest
  swarm or hide the alternatives by deduplicating only on agent identity.
- Selecting an agent location focuses that exact agent in the chosen swarm;
  selecting a swarm goes to that swarm. Navigation does not mutate membership.
- Cmd-P remains the navigation shortcut. Cmd-Shift-P remains command mode.
  Native menu, tooltip, help, custom bindings, and actual dispatch must agree.
- Agents with no open swarm belong to Add. Navigate's explicit “Add an agent…”
  action opens that separate surface while preserving the query. Closed work
  remains in History. A missing/stale navigation location never redirects to
  another swarm or changes membership.
- Entering/leaving `>` command mode keeps the same text editor mounted, so the
  immediately following select-all/delete or typing event keeps its focus.

### Add agent

- Build one shared Add interface for **New swarm, the floating +, and both
  split directions**. It must support existing agents and a clearly visible
  **New agent** action. A split must not immediately force the creation form.
- Existing-agent results on the left, attractive always-on preview on the
  right, inspired by fzf and the user's Swarms v4 prototype. New swarm may embed
  the component; + and Split can present it centrally as a modal.
- Remove the eye/preview toggle. Show a bounded, readable excerpt with agent
  identity and useful context; avoid raw terminal dumps, long separator rules,
  clipped ANSI/TUI debris, and competing selected/hovered rows. Preview must
  follow the actual keyboard/mouse selection and show an honest empty state.
- Use one unambiguous primary action: add here, or add at the requested split.
  “Go to agent” is wrong on the New swarm page. Keep the user in that tab.
- Adding an existing agent reuses it and leaves its source swarms intact.
  Avoid duplicate memberships. Decide a clear already-here/capacity state;
  never pretend an unavailable action succeeded.
- New agent from this surface preserves the original swarm/split destination,
  even if the active tab changes while a dialog or request is pending.
  Canceling preserves arrangement, zoom, focus, and the user's input.
- Darken the modal backdrop so the active dialog has clear visual focus.
  Apply the shared treatment consistently to app popups.

### Other agreed visual and interaction decisions

- Use one four-pane **SwarmIcon** everywhere a swarm is represented: search,
  History, native menus, and starters that open swarms. A real folder/project
  chooser can still use a folder symbol; keep the represented entity clear.
- Swarm location metadata: show the machine name for one machine, or
  **N machines** for multiple distinct machines.
- Models/account rows consistently use short account IDs without the literal
  word “Account”; do not mix email and ID presentation.
- Native menu order requested: **Harness · Swarm · Agent · Models · History ·
  Edit · View · Window · Help**. Keep standard supporting menus for native
  editing/window/help behavior. The reorder is implemented and checked in AppKit.
- New agent has one-click Codex / Claude Code / Cursor choices plus More for
  the full list, remembered choice, neat Advanced options, and a separate
  GitHub clone flow alongside choosing a local working folder.
- Keep existing effective shortcuts. In particular preserve Cmd-H/J/K/L and
  Cmd-arrows for focus, Cmd-S for layout, Cmd-R for refresh, and Cmd-B for Boss
  mode. Do not revive the previously rejected default-remapping proposal.
- Resizing uses restrained centered grips. Pane headers expose zoom and a
  menu with split right/down. Verify their actual geometry and discoverability,
  not just that callbacks exist.

## Current implementation and remaining work

**Implemented on the branch:** swarm/session retention, native tabs, layouts,
closed-work History, palettes, editable centered search and command mode,
keyboard customization, pane split/zoom controls, the simplified New agent
dialog, Harness branding, consistent short account labels, saved project-name
precedence, and independent machine loading while account metadata loads.
See [the progress log](harness-v2-progress.md) for individual checkpoints and
[the developer-tool audit](harness-v2-developer-tools-research.md) for research.

**Latest source changes:** Navigate is a separate compact directory with exact
swarm/agent destinations. The floating bottom-right +, New swarm search, and
both split actions share Add results, an always-on preview, and a New agent
action. Typed matches already in the target swarm say “In this swarm” and cannot
be added twice. Group additions skip existing members. Split requests preserve
the neighbor/direction and refuse stale layouts. Previews join wrapped prose,
remove terminal rules/recap headers, and show a bounded excerpt in a reading card.
The shared modal veil is darker and the eye toggle is removed. Old custom
bindings for that retired toggle no longer invalidate the rest of the keymap.

**Current first-use continuation:** every empty tab uses one inventory-driven
start page. With no existing work, it leads with **Start with one agent**, a
static workspace example, **Choose folder…** and separate **Clone repository…**.
Available existing work gets Add search, three direct agent choices and New
agent. Saved projects stay visible; the rest of the machine/project catalog is
behind Browse. A single usable local computer no longer needs a Machine dropdown
in the creation form. Delayed discovery enables Enter on the primary action
without stealing an explicit focus choice. Offline/linking cases expose their
next action. Large text stacks the layout, and New agent now uses the shared
darker modal veil. See [first-use details](harness-v2-appearance-onboarding.md).
Observed first-install/provider flows and onboarding conversion/time remain
unverified; do not infer them from these UI changes.

**Archived drafts:** both are superseded. The onboarding ideas were adapted into
the common page, without adding another first-tab-only component.

**Latest verification:** 1,262 desktop tests passed with one existing skip;
analyzer reports zero errors/warnings and 12 existing vendored infos. The last
native checks passed 51 keymap decoder and 344 AppKit assertions; this onboarding
pass changes no native source. Synthetic start-page/form captures with real
fonts were reviewed at 1280×800 and 880×560 with 2× text; they are not a real
native-session visual or latency measurement. Logs:
`/private/tmp/harness-onboarding-{full-tests-final,analyze-clean}.log`.
Navigate/Add timings and their exact scope are in
[the performance record](harness-v2-performance.md). The new navigation catalog
build measured 0.194 ms median / 0.264 ms p95 for 50 locations across 12 swarms.
Logs: `/private/tmp/harness-two-pickers-{full-tests-final,analyze-clean,native}.log`.

**Also saved:** [native benchmark tooling](../desktop/tool/native_benchmark/README.md)
and [shared-swarm collaboration research](harness-collaboration-design.md), which
were existing uncommitted work. Collaboration is a separate proposal/prototype,
not implemented multiplayer or a prerequisite for finishing this desktop pass.
The benchmark still needs compatibility fixes before another run: its prepare
script assumes the old `Harness V2` product name, its process check uses that
name, and its native initial-responder logic is the older version. Preserve its
isolation/focus guards. The performance notes explain the failed calibration.

## Previous terminal fix and verification

The user reported opening a project swarm with five terminals showing older
content instead of the latest output. Ordinary fresh/delayed five-pane fixtures
already reached the bottom. A targeted regression reproduced a separate concrete
cause: shrinking a captured 100-row TUI while its hidden cursor is parked near
the top deletes the newest rows from the local emulator.

`26a372e` adds `TerminalView.resizeBuffer` (default true); Harness sets it false.
The renderer reports the desired viewport without destructively resizing captured
remote cells. The daemon's resized keyframe replaces the grid. Repeated output
does not repeat the same resize request. New views show the latest output, while
returning to a deliberately scrolled view preserves the reading position.
The exact five-pane real-session screenshot still needs a direct recheck; do not
claim this reproducer proves every cause of that symptom.

The same checkpoint saves the existing first-agent naming change: an empty
default “New swarm” adopts its first agent's name; custom names and other tabs
are preserved. Tests cover subsequent additions and close/reopen behavior.

Historical checks for that terminal checkpoint:

- **1,244 desktop tests passed, one existing skip**, including the new four-case
  terminal regression file and the two swarm naming tests.
- Analyzer: **zero errors/warnings**, 12 existing vendored xterm informational
  diagnostics, using `--no-fatal-infos`.
- Native benchmark Python files pass syntax parsing; no new native benchmark
  run or accepted timing result is claimed.
- Both archived patches individually pass `git apply --check` against this
  source checkpoint. That does not validate applying them together or their
  compatibility with the new product decision.
- The archived picker previously passed 57 focused Flutter tests and
  51 keymap decoder + 343 AppKit checks before it was parked. Those results
  apply to the old draft only. Its final visual treatment still needs review.

The common onboarding continuation's macOS arm64 **Release build succeeded**
with `FLUTTER_TARGET=lib/main.dart`. Log:
`/private/tmp/harness-onboarding-release-build.log`. Computer Use still returns
`cgWindowNotFound` for the exact workspace bundle path. The new binary is built;
it has not been confirmed loaded in the running preview or visually verified
through native capture. Preserve this distinction when resuming.

The previous workspace Release build at **`2d3c024` succeeded**. The old preview (PID 29025)
was closed normally, then the exact workspace bundle was launched and verified
running as PID 15377 with identity `ai.autonomous.harness.v2`. Those PIDs are only
historical observations; recheck before any later process action. Build log:
`/private/tmp/harness-two-pickers-release-build.log`.

Live visual inspection remains unverified: Computer Use now lists the running
app, but getting its exact bundle path returned `cgWindowNotFound`. A bundle-ID
lookup is ambiguous with the old Debug copy in `/Users/ab/code/harness-app-v2`;
always use the exact workspace path. The successful build/process check is not
proof of native visual/input latency. Calibration previously failed with an
inactive/non-key benchmark window. Retry it only when new evidence establishes
that its isolated window can become active/key.

## Plan for the next session

1. **Confirm the latest source/build checkpoint.** The common onboarding
   continuation has a successful Release build; its running-window revision is
   not confirmed. The last confirmed relaunch was `2d3c024`. Review
   Navigate, Add, command mode, and the fresh terminal position in the native app
   when computer-use access works. Preserve real running agents and input.
2. **Observe genuine first use of the common start page.** Start with no
   account/runtime/agents/projects knowledge and record actual steps/errors to
   a usable agent. The folder-first path, workspace example and secondary
   catalog are implemented. Check fresh dependencies, provider sign-in, cloning,
   first task and adding a second agent; improve what the observation exposes.
   Preserve choices on failure and the distinction between Navigate and Add.
3. **Recheck fresh terminal positioning and real workflows** on disposable
   local/remote agents: startup, delayed snapshots, resizing, returning to a
   scrolled view, reconnect, paste, selection, and IME.
4. **Measure native responsiveness** under representative retained/output load,
   then close remaining visual/platform/release qualification gaps. Maintain
   the draft PR and keep its description honest about what's still unverified.

## Acceptance criteria

### Navigation and adding

- One agent in three swarms yields three explicit usable destinations. Enter
  focuses the chosen pane in the chosen swarm without altering membership.
- The first character typed after navigation reaches only the selected agent.
  Hidden/offscreen/zoomed destinations are revealed while retained sessions and
  reading positions survive switching away and back.
- All three Add entry points can add an existing agent and create a new agent.
  Both split directions preserve their exact original placement. Source swarms
  remain intact, and existing-agent addition starts no duplicate runtime.
- Already-present, offline, removed, changed-membership, full-capacity, canceled,
  and failed asynchronous actions produce a clear result without modifying the
  wrong swarm or losing a draft. Late completion revalidates its destination.
- Arrow keys, Enter, Escape, Cmd-A/Delete, paste, and IME work in each input.
  One selected result drives the preview; repeated output cannot steal focus.
- The toolbar has Navigate and Notifications; only the tab-strip + creates a
  swarm. The floating Add + is bottom right and does not cover the terminal prompt.
- The Add preview is always present when meaningful, readable at small/large
  window sizes, bounded, and useful for choosing an agent. No eye toggle, raw
  overflow, or ambiguous “Go to agent” action in the local Add workflow.

### First impression and visual quality

- A first-time developer can identify the primary next step without first
  learning machines, projects, swarms, and agent-account configuration.
- The happy path reaches a real usable agent with the fewest meaningful choices;
  joining existing work and starting fresh are both discoverable. Missing tools,
  authentication, connectivity, and failed creation give an actionable next step.
- Observe first-use completion and confusion directly. “Hook everyone instantly”
  is the user's aspiration, not a measured 100% conversion claim. Record actual
  steps/time/errors before making onboarding performance claims.
- One icon per concept and consistent labels/contrast across native and Flutter
  controls. Six coordinated palettes remain legible; system text scaling,
  keyboard focus indicators, accessibility labels, and narrow windows work.
- Modals clearly separate foreground from background. Grips, splits, zoom,
  menus, and account rows look intentional with real fonts and content.

### Correctness and performance

- Fresh views land at the latest output, including tall/delayed snapshots and
  five-agent project swarms. Revisited scrolled-up views retain their position.
- Shared agents retain one session/buffer/controller; hidden output does not
  repeatedly lay out/paint hidden terminals or reconstruct unchanged catalogs.
- Report cold/warm p50/p95/p99 for native event-to-raster typing/focus/tab changes
  with 16 and 48 retained terminals, idle and under output load, when valid
  foreground measurement is available. Report machine/build/load and raw sample
  limits. Synthetic search CPU, Flutter raster, network RTT, and physical
  key-to-display latency are different measurements and must stay distinct.
- Reconnect preserves readable output/drafts and does not blindly replay input
  or take over another controller. Real remote reconnect still needs evidence.
- Run meaningful affected tests, analyzer, native decoder/titlebar checks for
  native changes, and a Release build before claiming a new preview is loaded.
  Full desktop regressions must pass before promoting the PR from draft.
- Verify macOS native behavior directly and qualify Linux on a Linux host.
  Windows support is unexercised; do not claim it from macOS test success.

## Implementation and verification map

| Area | Start here |
| --- | --- |
| Workspace orchestration, picker routes, split/new-agent context | `desktop/lib/screens/swarm_screen.dart` |
| Search data, actions, destinations | `desktop/lib/state/swarm_search.dart`, `swarm_navigation.dart`, `swarm_catalog.dart` |
| Distinct Navigate and shared Add/welcome UI | `desktop/lib/widgets/swarm_navigator.dart`, `swarm_switcher.dart`, `swarm_inline_search.dart`, `swarm_search_input.dart`, `swarm_welcome.dart` |
| Preview extraction | `desktop/lib/terminal/search_output_preview.dart` |
| Native tabs, toolbar, menus | `desktop/macos/Runner/SwarmTitlebar.swift` |
| Key ownership and customization | `desktop/lib/shortcuts/`, `desktop/tool/check_keymap_native.sh` |
| Membership, retained panes and runtime | `desktop/lib/state/app_state.dart`, `swarm.dart`, `terminal_pane.dart` |
| Terminal viewport fix | `desktop/lib/widgets/terminal_panel.dart`, `desktop/third_party/xterm/lib/src/ui/render.dart`, `desktop/test/terminal_initial_output_test.dart` |
| Remote resized snapshot | `cli/src/lib/terminalStreamManager.ts`, `desktop/lib/terminal/terminal_session.dart` |
| Design/research history | `docs/harness-v2-{progress,keyboard-system,appearance-onboarding,developer-tools-research,prototype-review,performance}.md` |

## Toolchain and operating boundaries

Read `desktop/CLAUDE.md`, but treat its old integration-test/sidebar/architecture
descriptions as historical where current source differs. No applicable AGENTS.md
was found in this checkout or its ancestors during the work.

This checkpoint used **Flutter 3.47.2 / Dart 3.13.2**, Swift Package Manager,
and Xcode on Apple Silicon. On the other computer install/select that compatible
SDK; the old `/private/tmp/harness-v2-flutter` path is not a portable dependency.
From `desktop/`:

```sh
flutter config --enable-swift-package-manager
flutter pub get
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
bash tool/check_keymap_native.sh /absolute/path/to/flutter-sdk
```

Enable SPM before pub get. Do not commit a CocoaPods fallback rewrite, generated
build files, caches, credentials, or real account/terminal state. The vendored
xterm contains required patches; do not replace it with the pub.dev package.
Build instructions and prior measurements are in the progress/performance notes.

The normal entry point is `desktop/lib/main.dart`. The public app/binary name
is **Harness**; the development bundle ID remains `ai.autonomous.harness.v2` to
preserve its separate state. Workspace Release path on the old computer was
`desktop/build/macos/Build/Products/Release/Harness.app`; the installed Harness
was a separate process. Recheck exact bundle paths/PIDs before normally quitting
or relaunching a preview. Do not launch a competing duplicate or use a real
agent's prompt as a test input.

Keep tests/benchmarks isolated with temporary stores and synthetic/disposable
transports. Do not upgrade or restart the user's production CLI/daemon for
qualification. Follow the requested `app-v2` checkpoint workflow; publishing a
release, merging the draft, and production end-to-end operations are separate
tasks. Keep handoff notes current as work progresses.
