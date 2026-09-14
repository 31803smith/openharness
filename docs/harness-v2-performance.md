# Harness V2 performance checks

Measured on 2026-09-12, with retained-canvas, idle-work, background-output and keyboard attention continuations on 2026-09-13, using Apple M2 Max, macOS 26.6.2, Flutter 3.47.2 and Dart 3.13.2.

The explicit benchmark runs in the headless Flutter test runner with isolated synthetic sessions. It never opens a sample-data app or connects to a real agent. Run it from `desktop/`:

```bash
flutter test --no-pub --reporter expanded test/benchmarks/swarm_benchmark.dart
```

It prints `SWARM_BENCH` JSON records. Its filename deliberately does not end in `_test.dart`, so ordinary correctness runs do not include timing measurements.

## Concurrent machine discovery (2026-09-13)

Agent inventory and terminal capability requests now start together after the machine handshake. The small capability request is sent first because the CLI dispatches frames through a per-client FIFO; it can answer that request before assembling project metadata for the agent list. The list becomes visible as soon as it arrives. Existing panes attach only when both inventory and protocol information are available, without changing focus or membership.

Readiness has a bounded wait. Its elapsed time is subtracted from the inventory's existing ten-second budget; capabilities retain an eight-second reply budget that begins after the handshake. Pending capability work is shared across a failed inventory request and its retry. Close, unlink, expired waits, removed machines and signed-out sessions cannot queue new metadata requests from a late completion.

Both initial regressions failed before the change. The affected suite passed 107 checks; a subsequent 14-check discovery/readiness run includes a new combined AppNotifier and actual WebSocket test against a disposable loopback peer. The peer receives both requests before releasing either reply, and the app publishes the agent list before the capability reply. This verifies the request graph and behavior; it is not an observed remote or native latency measurement. Logs: `/private/tmp/harness-v2-machine-loading-{before,tests,transport-tests}.log`.

## Workspace discovery without a profile dependency (2026-09-13)

After CLI sign-in and daemon readiness, machine discovery used to wait for the account profile. Refresh recovery repeated that dependency whenever no profile was known. The requests now run independently; only one profile request is kept in flight, and a completed response updates the account separately. A failed profile does not delay machine error recovery or require another sign-in.

The regression fixture leaves the profile unresolved and verifies that launch/sign-in finish, machine inventory and agent capabilities arrive, and refresh completes. It also verifies late account notification, a subsequent profile retry and discarded responses after sign-out/disposal. The initial four regressions failed against the previous code; all 118 affected startup and workspace checks now pass. Logs: `/private/tmp/harness-v2-profile-startup-{before,tests}.log`.

This removes a serial dependency; it is not a timed benchmark or a claim of a fixed amount saved. The production API's existing receive timeout is 30 seconds, but the fixture does not simulate that as an observed user delay. Real native launch, provider sign-in and time to first useful agent remain separate measurements.

## Persisted settings initialization (2026-09-13)

The font and appearance stores previously restored five keys with five separate file-lock, permission-check and JSON-read cycles. Each group now uses one requested-key snapshot, reducing that work to two cycles. File locking, private permissions, corrupt-file quarantine and future-schema protection remain in the same storage path. Snapshots are not cached; an intervening write is visible to the next read, including writes through another store instance. No unrelated credential keys are returned to the preference stores.

The independent stats file loads alongside these groups, and `main()` starts the keyboard file/watch setup at the same time. The window still waits for all settings and keyboard configuration before becoming usable. Counters finish loading before any agent events can increment them.

Run the explicit isolated benchmark from `desktop/`:

```bash
flutter test --no-pub --reporter expanded test/benchmarks/startup_benchmark.dart
```

One before/after run used 20 warmups and 100 samples for each workload. Each sample creates fresh store objects over temporary files containing five synthetic preferences, counters and, for the combined workload, a valid keyboard override with its real directory watches. Object construction is outside the timer. Filesystem caches are warm; this runs in the headless debug test runner.

| Initialization workload | Before median / p95 | After median / p95 |
| --- | ---: | ---: |
| Font, appearance and counters | 29.505 / 32.234 ms | 12.149 / 13.468 ms |
| Settings plus keyboard read, validation and watches | 31.877 / 34.919 ms | 13.042 / 14.295 ms |

This measures one initialization step, not a cold process launch, native first-frame presentation, agent connection or input latency. No production settings were read. Logs: `/private/tmp/harness-v2-startup-benchmark-{before,after}.log`.

All 58 focused startup, file-store, appearance, font, counter, palette and keyboard checks passed (`/private/tmp/harness-v2-startup-tests.log`). Startup regressions now inject every store instead of allowing appearance and stats to reach their global defaults. They cover complete restoration, empty storage, overlapping delayed loads, the readiness barrier and failed appearance reads while counters are still pending. Batch-store checks cover selected keys, an intervening write/delete, empty requests, corruption and newer schemas; existing private-file permission checks still pass.

## Native search field updates (2026-09-13)

The production bridge was sending the same placeholder hint back to AppKit for every native query edit. A regression observed five reverse-channel `searchState` messages for the five-query burst `w`, `wo`, `wor`, `work`, `work 木`, including interleaved catalog updates. The revised bridge sends zero for that burst and one changed hint when entering command mode. It still sends an intentional query replacement when the user invokes Search commands.

The bridge remembers the latest native query even when it sends nothing, so a later catalog refresh cannot echo that older query over a newer native edit or composition. A typed query/hint snapshot replaces JSON encoding on each edit. Native search also stops maintaining the unmounted Flutter text controller. Result filtering and rendering still occur as needed; this does not establish a measured latency reduction or eliminate the cost of opening the search catalog.

The redundant-message check failed before the change (`/private/tmp/harness-v2-search-echo-before.log`). Final focused behavior/render checks passed (`/private/tmp/harness-v2-search-arrival-final-tests.log`); the hidden AppKit field separately preserved its editor, marked text and caret through attention/palette updates (`/private/tmp/harness-v2-search-arrival-native.log`). Real native input-to-display calibration remains paused as described below.

## Local Git context recovery (2026-09-13)

[Dart's filesystem watch documentation](https://api.dart.dev/dart-io/FileSystemEntity/watch.html) warns that events can coalesce or arrive out of order, and that watches end when their target disappears or the watcher stops. [Git's repository layout](https://git-scm.com/docs/gitrepository-layout) distinguishes the working tree's `.git` pointer, worktree-specific HEAD and shared configuration through `commondir`. The compatibility reader now observes those relationships and treats a subscription as fallible.

The cache still holds at most 256 working folders. Each entry watches at most three nonrecursive directories, filters metadata events, and retains the 100 ms debounce. Changed targets cancel obsolete subscriptions; a replaced directory rebinds its watches even when the path is reused. Watch loss schedules one refresh and delays another subscription attempt for one minute. Normal daemon discovery rechecks one-minute-old entries even if their watches appear live; no periodic timer was added. Removed working folders clear context. Work is serialized per entry, so a slow older result cannot finish after a newer one and replace it.

Reads traverse at most 32 ancestors and request at most 64 KiB plus one byte per metadata file, rejecting oversized/invalid text. They open no Git processes, read no terminal output, send no input/network traffic and perform no work on the render path. This limited compatibility reader does not replace Git's full config/environment resolution or richer daemon metadata.

All three stale-cache regressions failed on the earlier code. The final focused run passed 38 tests, including directory and common-path changes, ended/failed/unsupported watches, missed events, deletion, same-path replacement, serialized slow reads and disposal. The preexisting real temporary-filesystem worktree watch also passes; synthetic watchers cover failure ordering without relying on OS timing. Logs: `/private/tmp/harness-v2-git-watch-{before,tests,analyze}.log`. This establishes recovery and bounded work; it is not a new native latency measurement.

## Native calibration remains unmeasured (2026-09-13)

A fresh disposable Release copy of the existing native benchmark built at `/private/tmp/harness-native-benchmark-4t74nfhn`. Its separate bundle identity, temporary store, blocked networking and synthetic retained terminals isolate it from real agents. AppKit events are posted only to that fixture's own queue. The planned metric joins each observed input to Flutter's matching frame number and raster-finish timestamp; it excludes network and physical display latency. [Flutter's FrameTiming reference](https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html) describes those fields and recommends profile/release performance collection. The distinction between input latency under load and throughput follows the measurement discussion in [Dan Luu's terminal study](https://danluu.com/term-latency/); its old terminal rankings are not treated as current comparisons.

The first calibration stopped before samples because content focus could not be established. Inspection found that its driver requested focus on the wrapper view; the production titlebar correctly uses the Flutter view controller. Only the disposable copy was corrected to match that responder and to report active/key state separately. The rebuilt calibration then stopped with **key=false, active=false, visible=true**. Both runs exited without accepted timings. The guards were retained, the original untracked benchmark source was left unchanged, and the real preview reopened after the fixture exited.

Artifacts: `/private/tmp/harness-v2-native-prepare-current.log`, `/private/tmp/harness-native-benchmark-4t74nfhn/{build,rebuild-controller}.log`, `/private/tmp/harness-v2-native-calibration-20260913{.json,.log,-run.log}` and `/private/tmp/harness-v2-native-calibration-controller{.json,.log,-run.log}`. Do not retry the calibration until new evidence establishes that the disposable native window can become active/key. These failures provide no p50/p95/p99 or input-to-display result.

## Search match emphasis (2026-09-13)

Highlighting runs only for built result rows, sharing ranking's field scores and rune-based subsequence matching. The visible labels preserve grapheme boundaries and do not change ranking. A label longer than 1,024 UTF-16 units stays plain; up to twelve distinct terms from the first twelve query terms are considered, each at most 128 units, against fields at most 4,096 units. Empty queries stay on the plain-text path.

The isolated debug fixture measures the field selection and two labels for ten rows, using 20 warmups and 100 samples. Normal labels use “Fix authentication in Payments” with “ath payments”; the stress case uses a 511-character fuzzy title and a 127-character term repeated twelve times. Before sorting intervals and deduplicating terms, stress-case median/p95/p99 were 22.084/22.863/23.028 ms. The final implementation measured:

| Ten-row workload | Median | p95 | p99 |
| --- | ---: | ---: | ---: |
| Ordinary labels | 0.069 ms | 0.263 ms | 0.305 ms |
| Long fuzzy labels | 0.353 ms | 0.455 ms | 0.558 ms |

This measures CPU work to construct emphasis runs in the headless debug runner, not layout, rasterization, native typing or transport latency. The ranking algorithm itself is unchanged. Logs: `/private/tmp/harness-v2-search-highlight-render.log` (initial) and `/private/tmp/harness-v2-search-highlight-final.log` (final). The temporary renderer/measurement source is `/private/tmp/harness-v2-search-highlight-render.dart`.

## Optional search output preview (2026-09-13)

Preview is off by default. With preview enabled, changing the selected agent reads at most 160 retained rows × 192 cells, stopping after 12 nonblank lines. Query edits that keep the same selection reuse the snapshot without reading the buffer or scanning open panes again. There are no output listeners, periodic refreshes, network calls or terminal attachments. The tooltip explains that toggling preview off/on refreshes its snapshot.

An isolated debug-Dart fixture used a 300-column, 120-row terminal with 4,000+ retained rows, 200 warmups and 1,000 samples. Extraction of 12 output rows took **24 µs median / 33 µs p95 / 479 µs max**. Scanning 160 blank rows took **69 µs median / 84 µs p95 / 347 µs max**. Artifacts: `/private/tmp/harness-v2-preview-benchmark.dart` and `/private/tmp/harness-v2-search-preview-final-render.log`.

These measurements cover only extraction CPU time on the shared workstation. They do not measure result ranking, Flutter layout/paint, AppKit event handling, display latency or network round trips. Separate correctness checks cover Unicode, bounds, snapshot caching and unchanged query/input/terminal ownership.

## Unified search catalog and typing (2026-09-13)

The catalog benchmark now also exercises the production `SwarmSearchController`:
2,000 agents across eight machines and 50 projects, producing 2,059 searchable
destinations. It measures opening/disposing the controller, changing queries,
and searching inside one machine. Each operation uses 20 warmups and 100 samples;
resetting the query happens outside the measured interval. No widgets, sockets,
real agents, disk discovery, native field editor or display are involved.

Catalog construction now indexes machine membership and agent identities once,
instead of scanning all destinations again for every machine and project.
Aggregate project/Swarm metadata excludes repeated fields. Building an unfiltered
agent list no longer formats searchable text for every agent. Ranking stops
checking metadata after a title match that already outranks it, while continuing
past fuzzy title matches that better metadata can outrank. Exact whole-title
matches retain their first-place priority; recency and deterministic ties remain.

Sequential headless debug measurements on the same workstation:

| Operation | Before median / p95 / p99 (ms) | After median / p95 / p99 (ms) |
| --- | ---: | ---: |
| Build unified catalog | 6.776 / 7.482 / 7.810 | 3.405 / 3.846 / 4.238 |
| Open and dispose search controller | 8.212 / 9.121 / 9.469 | 4.637 / 4.980 / 5.357 |
| Query `agent` | 1.696 / 1.854 / 1.904 | 1.067 / 1.160 / 1.302 |
| Query `agent 12 machine 3` | 1.425 / 1.621 / 1.655 | 0.743 / 0.856 / 0.912 |
| Fuzzy query `agn12` | 0.915 / 1.068 / 1.141 | 0.676 / 0.789 / 0.866 |
| Query `project 12 main` | 1.525 / 1.659 / 1.746 | 1.019 / 1.204 / 1.332 |
| Query with no matches | 0.638 / 0.786 / 0.804 | 0.446 / 0.608 / 0.685 |
| Fuzzy query inside one machine | 0.115 / 0.135 / 0.171 | 0.122 / 0.147 / 0.260 |

Median catalog construction fell by 50%, and the controller open/dispose cycle
by 44%. Result counts stayed identical for every measured query. The scoped query
did not improve; its unchanged filtering path and higher tail observation are
retained here. Welcome text filtering was also effectively unchanged (median
1.210 → 1.217 ms), while project grouping fell from 1.457 to 0.615 ms by avoiding
unused search strings. An unchanged catalog still reuses the same snapshot.

These are shared-workstation debug CPU observations, not native keystroke or
physical-display latency. Host load and JIT affect them; 100 samples provide only
a limited tail estimate. This change makes no tab-switch latency claim. The
baseline and final logs are `/private/tmp/harness-v2-search-perf-before.log` and
`/private/tmp/harness-v2-search-perf-final.log`; the intermediate measurement is
preserved in `/private/tmp/harness-v2-search-perf-after.log`.

```bash
flutter test --no-pub --concurrency=1 --reporter expanded test/benchmarks/swarm_benchmark.dart --plain-name 'large live catalog CPU benchmark'
```

## Recorded measurements

| Operation | Earlier median / p95 | After native/canvas polish median / p95 |
| --- | ---: | ---: |
| Search 2,000 agents across 8 machines | 1.06 / 1.13 ms | 1.16 / 1.34 ms |
| Group the same catalog into 50 projects | 1.14 / 1.27 ms | 1.31 / 1.52 ms |
| Switch tab and pump a frame: 4 swarms, 16 terminals | 18.45 / 25.88 ms | 24.32 / 31.76 ms |
| Switch tab and pump a frame: 12 swarms, 48 terminals | 14.51 / 16.95 ms | 19.40 / 22.14 ms |
| Decode and parse a 16 KiB ASCII output frame | 0.51 / 0.68 ms | 0.55 / 0.73 ms |
| Decode and parse a 16 KiB Unicode output frame | 0.31 / 0.35 ms | 0.34 / 0.43 ms |

That repetition followed the native/canvas polish while the workstation was in active use. All five benchmark cases passed and retained rebuild counts stayed at 1,491 and 1,625, but timings were higher across all workloads. This was not a controlled paired comparison, so it neither isolates a cause nor establishes unchanged user-visible performance. Preserve this result and measure under controlled load in the native release app; do not report only the faster earlier run. Its local log is `/private/tmp/harness-v2-benchmark-polish.log`.

Catalog operations use 20 warmups and 100 samples. Each terminal has 1,000 scrollback lines; the window is 1280 × 800 with four visible terminals. Tab checks warm up for three full cycles, then take 60 samples. They retain one renderer per session and include Flutter frame work and test-runner overhead. Network, persistence I/O, AppKit titlebar rendering and physical display latency are outside these measurements.

These are **debug CPU measurements**, not end-to-end input latency or release frame budgets. JIT warming and host load affect timings; the later 12-swarm case being faster does not establish that more tabs make the app faster. Use the structural counts below to assess the specific optimization.

The output checks call the production `TerminalSession.handleBinary` with 16 KiB packets that repeatedly repaint one row, keeping scrollback size fixed. Each uses 20 warmups and 100 samples. They include the normal frame queue, UTF-8 decoder and terminal parser, with transport callbacks isolated; they create no widgets and exclude painting. Run only these checks with `--plain-name 'terminal output CPU benchmark'`.

## Reduced work when switching tabs

The first improvement retained hidden panes' widget configurations as well as their renderers. It reduced a 16-terminal switch from 2,480 to 1,491 widget rebuilds; the 48-terminal case rebuilt 1,625 widgets. Moving GlobalKey subtrees between the visible layout and parked list still invalidated inherited dependencies when changing tabs, zoom or presets.

The current Swarm canvas keeps every visited terminal under one mounted scroll view and Stack, changing its rectangle without reparenting it. Healthy visible cells and unchanged headers retain their widget configuration too. Connection/setup states remain uncached, and cached header actions resolve the current widget. Session replacement updates hidden views; showing a pane applies current machine and agent metadata. Background output continues reaching the session buffer.

The paired continuation used the same benchmark before and after these changes, adding 60 focus-change/frame samples to each existing tab workload:

| Workload | Before median / p95 | After median / p95 | Rebuilds before → after |
| --- | ---: | ---: | ---: |
| Tab switch: 4 Swarms / 16 terminals | 20.924 / 26.020 ms | 12.226 / 17.116 ms | 1,491 → 917 |
| Tab switch: 12 Swarms / 48 terminals | 14.151 / 17.363 ms | 8.925 / 10.497 ms | 1,625 → 1,051 |
| Focus change: 4 Swarms / 16 terminals | 6.764 / 7.909 ms | 5.284 / 6.613 ms | 980 → 602 |
| Focus change: 12 Swarms / 48 terminals | 5.150 / 6.260 ms | 4.586 / 5.535 ms | 1,114 → 736 |

Median tab CPU time fell by 42% and 37%; focus CPU time fell by 22% and 11%. These remain headless debug measurements with host-load and JIT variability, excluding native input and the physical display. Stable-ancestry tests and lower rebuild counts provide structural evidence alongside the timings. Logs: `/private/tmp/harness-v2-stable-canvas-before.log` and `/private/tmp/harness-v2-stable-canvas-measured.log`. Reproduce with:

```bash
flutter test test/benchmarks/swarm_benchmark.dart --no-pub --reporter expanded --plain-name 'tab-switch CPU benchmark'
```

Regression checks cover renderer identity and element ancestry, hidden geometry, input ownership, selection, first-frame per-Swarm scroll restoration, renaming while hidden, session replacement and fresh header callbacks. Swarm geometry matches the legacy layouts across fixed presets and auto grids. Changing font metrics at the same point size now invalidates the minimum-tile cache and immediately updates grid dimensions.

Rapid navigation also coalesces pending arrangement writes. While the first write is in flight, only the latest subsequent snapshot is retained. Tests with 100 rapid tab changes verify that the first and final snapshots are written, including recovery after the first write fails. Normal quit waits for the final snapshot with a one-second bound for stalled storage.

Incoming binary data now skips unrelated sessions before awaiting the matching renderer queue. This removes one async scheduling turn per unrelated view from each frame's dispatch, while retaining socket FIFO, current stream identity and machine isolation. This change is verified by routing tests; the CPU table above does not measure network delivery.

Settings route and section fades are removed: the former opening/closing durations were 170/120 ms for the route and 200/90 ms for the section switcher. Both now present their destination immediately. Existing Settings, modal and route checks pass; this change removes configured animation time, not all possible input or rendering cost.

## Idle cursor and keyboard work

Every mounted terminal previously started a 500 ms periodic cursor timer, including retained hidden views. Its callback checked focus and visibility after waking, and the focused terminal continued blinking when the native window was inactive.

The cursor clock now exists only while the terminal is visible, focused, accepting input, writable, in an enabled ticker subtree, and in the active application. Focus, session status, route visibility and application lifecycle events start/stop it directly. Stopping restores the local bright cursor phase while preserving the remote program's cursor visibility. The ticker-mode listener updates the clock without rebuilding the retained subtree.

The paired isolated measurement counts actual periodic timer creation and callbacks through a delegated Dart zone. Each observation advances the widget runner's fake clock by five seconds:

| Retained terminals | View/window | Active timers before → after | Callbacks in 5 s before → after |
| ---: | --- | ---: | ---: |
| 16 | Four visible panes, one focused | 16 → 1 | 160 → 10 |
| 48 | Four visible panes, one focused | 48 → 1 | 480 → 10 |
| 16 | Inactive window | 16 → 0 | 160 → 0 |
| 48 | Inactive window | 48 → 0 | 480 → 0 |
| 16 | Empty New swarm | 17 → 1 | 170 → 10 |
| 48 | Empty New swarm | 49 → 1 | 490 → 10 |

The empty Swarm's remaining timer belongs to its focused search field caret. These synthetic sessions start in controlling state without network heartbeats, so the table measures UI timer activity rather than total process wakeups, CPU usage, battery life or display latency. Real session heartbeats and output delivery continue independently. Baseline and final-source logs: `/private/tmp/harness-v2-idle-before.log` and `/private/tmp/harness-v2-idle-measured.log`.

```bash
flutter test test/benchmarks/terminal_idle_benchmark.dart --no-pub --reporter expanded
```

Global link-modifier handlers are now registered only while a visible link is under the pointer, removing the per-retained-terminal listener from ordinary keyboard input. Hidden views clear hover state and skip link refresh callbacks. Tests cover focus/tab/zoom changes, covered routes, window inactivity and resumption, session replacement, read-only/connection ownership, and a stationary link pointer across session replacement and modifier release. That continuation's full suite passed 1,010 tests with one skip.

## Rendering background output

Offstage had stopped hidden panes from painting, but their renderers still listened to every terminal write, requested layout and calculated native caret coordinates. The new `TerminalView.renderingEnabled` flag defaults to true; `TerminalPanel` supplies its visibility, and a disabled enclosing ticker mode also suspends the leaf renderer. A suspended renderer detaches its output listener and skips viewport/scroll reconciliation. The session continues parsing incoming output into its existing buffer.

Showing the view requests one layout against the current buffer. It preserves a manually chosen scroll offset or follows the new tail, and reconciles changed terminal dimensions even when the pane's pixel size is unchanged. Matching dimensions skip emulator resize, preserving a TUI's scrolling margins. Session/keyframe changes still update retained views as needed.

The paired headless workload starts with 1,000 history lines per terminal and four visible panes in a 1280×800 window. Each sample writes four short ANSI updates to one existing row in every selected terminal, then pumps Flutter. It uses 20 warmups and 60 measured samples, excluding sockets, binary decoding and physical display timing:

| Retained terminals | Output destinations | Before median / p95 | Final median / p95 | Hidden renderers needing layout before → after |
| ---: | --- | ---: | ---: | ---: |
| 16 | 12 hidden terminals | 0.901 / 1.366 ms | 0.110 / 0.169 ms | 12 → 0 |
| 16 | All 16 terminals | 1.117 / 2.027 ms | 0.757 / 0.921 ms | 12 → 0 |
| 48 | 44 hidden terminals | 1.255 / 1.641 ms | 0.206 / 0.227 ms | 44 → 0 |
| 48 | All 48 terminals | 1.574 / 1.836 ms | 0.766 / 0.945 ms | 44 → 0 |

Hidden-only bursts no longer schedule a Flutter frame in this workload. Their median CPU cost fell by 88% and 84%; the mixed visible/hidden workloads fell by 32% and 51%. These are headless debug CPU observations with host-load/JIT variability, not native latency or total app CPU reductions. Logs: `/private/tmp/harness-v2-background-before.log` and `/private/tmp/harness-v2-background-measured.log`.

```bash
flutter test test/benchmarks/terminal_background_benchmark.dart --no-pub --reporter expanded
```

Native caret coordinates now coalesce into one callback after the frame, using final scroll offsets and ancestor positions. Only a focused, enabled renderer schedules the update. Focus and restored layout refresh the caret even without new output. A test sends 30 cursor-changing writes before a frame and verifies one final native caret message; the terminal input dispatch path remains unchanged.

Four new checks cover real `TerminalSession.handleBinary` output while hidden, selection/manual-scroll/follow-tail preservation, first-frame raster pixels, changed terminal dimensions, unchanged TUI scroll margins, covered routes with a retained widget, and native caret coordinates on restoration. The final full suite passes 1,014 tests with one skip.

## Terminal output allocations

Ordinary output packets now decode directly from their existing byte view. Previously every packet was copied into a joined list and copied again to select the decodable prefix. A joined buffer is still used when a UTF-8 character crosses packet boundaries, and the decoder reads a bounded range without copying that prefix. Malformed-byte replacement and terminal recovery behavior are unchanged.

In the paired headless checks, median decoding-and-parsing time fell from 0.683 to 0.514 ms for the ASCII workload and from 0.484 to 0.314 ms for Unicode. Corresponding p95 values were 1.088 to 0.680 ms and 0.686 to 0.348 ms. These measurements establish the benefit for these workloads; they do not measure user-visible latency or every terminal output pattern. Existing terminal-session regressions cover split UTF-8, compressed keyframes, parser sequences and recovery.

## Jump navigation

Cmd+P opens without a route transition or backdrop filter. Search normalizes a catalog once on opening and refreshes it on app-state changes; typing ranks that snapshot in memory without discovery, disk or network calls. List rows are built on demand. Recent-work history retains at most 64 string identities, not controllers or terminal buffers.

Existing-view activation is focus-only. It changes destination Swarm and pane focus in one notification, preserves its arrangement, and never retries or takes over the terminal. Selecting a Swarm preserves its saved focus and zoom. A fresh view is an explicit action, revalidated against current membership and the originally captured destination.

The continuation's headless debug run produced the following measurements in `/private/tmp/harness-v2-benchmark-jump.log`:

| Operation | Median | p95 |
| --- | ---: | ---: |
| Build jump catalog: 2,000 agents, 8 machines | 1.424 ms | 1.689 ms |
| Rank cached jump catalog for `agent 12 machine 3` | 1.059 ms | 1.154 ms |
| Welcome search: same 2,000 agents | 1.119 ms | 1.236 ms |
| Project grouping: 50 projects | 1.239 ms | 1.359 ms |
| Switch and pump: 4 Swarms / 16 terminals | 20.420 ms | 30.016 ms |
| Switch and pump: 12 Swarms / 48 terminals | 16.105 ms | 18.258 ms |
| Decode and parse: 16 KiB ASCII | 0.531 ms | 0.693 ms |
| Decode and parse: 16 KiB Unicode | 0.330 ms | 0.362 ms |

All five benchmark cases passed; retained rebuild counts remained 1,491 / 1,625. This repetition was not a controlled paired comparison with the prior run. The new search measurements establish CPU cost for that query and catalog, excluding widget layout, AppKit input and physical display. Correctness checks verify the first terminal key after a jump goes only to its destination, but they do not measure native keystroke latency.

## Waiting work and keyboard scrolling

Cmd+Shift+I opens the existing bell's **Needs input** surface without the prior 140 ms dialog transition or backdrop blur. Its live catalog uses the same fuzzy ranking as Cmd+P, including question text. No discovery, network call, polling or aging timer runs on each keystroke. Only visible and cached list rows are built.

Keyboard selection in both pickers now adjusts the scroll offset during the key event, before painting. The earlier post-frame scroll could leave the new selection offscreen for a frame. Tests require the selected row to be visible after a single pump on each arrow movement, including past the bottom edge. Live catalog changes still reveal selection after the new list dimensions exist, with at most one scheduled reveal callback.

Nine new state/widget checks pass, alongside the extended native command guards. They cover immediate search focus, Ctrl-N/P, 2× text at 880×600, stale question/view guards and the cross-Swarm round trip: select a waiting agent, deliver input only there, then Cmd+P / Return and deliver input only to the prior agent. That continuation passed 1,023 tests with one skip. These are frame-order and correctness checks, not measurements of physical input-to-display latency.

## Terminal Find and tab hover

Cmd+F mounts a small field in the focused pane's existing header. It neither changes the terminal viewport nor covers output. Cmd+G / Cmd+Shift+G and Enter / Shift+Enter select matches; Escape restores the original scroll bookmark and input focus. A real keyframe preserves the text controller, caret, query and focus while replacing the emulator. This test also exposed a resize debounce callback whose handle was dropped by a keyframe's immediate flush; the flush now cancels that pending callback first.

The literal Unicode search joins soft-wrapped lines and keeps hard lines distinct. An optional index reuses decoded text from unchanged line identities and versions, yields after about 1.5 ms of scan work, and stores one offset checkpoint per 64 matches. Only the selected search result owns an anchor; the renderer highlights that result separately from normal terminal selection. Already-valid matches remain navigable while output refreshes. Hidden, covered and inactive searches release the index and listeners, retaining the query and selected location. Closing Find leaves no search listener or timer. Line-version increments remain in the ordinary buffer mutation path.

Sequential isolated benchmarks (`--concurrency=1`, with no other test/build running) use 10,000 retained rows at 120 columns. These are debug event-loop times including cooperative yields, excluding native input, display, transport and file search:

| Operation | Median | p95 |
| --- | --- | --- |
| Cold query, one observation | 42.181 ms | — |
| Changed query over cached text, 40 samples | 7.183 ms | 15.497 ms |
| Live single-row output refresh, 40 samples | 2.809 ms | 7.452 ms |
| Move to next match, 40 samples | 0.004 ms | 0.026 ms |

Background-output comparison before/after line versioning and Find:

| Retained terminals / scope | Before median / p95 | After median / p95 |
| --- | --- | --- |
| 16 / hidden | 0.120 / 0.169 ms | 0.118 / 0.165 ms |
| 16 / all | 0.790 / 1.665 ms | 0.818 / 1.362 ms |
| 48 / hidden | 0.195 / 0.218 ms | 0.205 / 0.246 ms |
| 48 / all | 0.736 / 0.912 ms | 0.774 / 1.048 ms |

All hidden-output samples still reported zero hidden renderers needing layout and no scheduled frame. Several median timings increased by about 4–5%; these shared-workstation observations do not isolate that difference or establish zero overhead. Logs: `/private/tmp/harness-v2-find-benchmark.log` and `/private/tmp/harness-v2-find-output-before.log`. The earlier overlapping benchmark run was replaced by this sequential result.

The final full suite passes 1,035 tests with one skip; the analyzer reports zero errors/warnings and 12 existing vendored infos. Find checks cover literal/wide-character mapping, reflow and buffer changes, 50,000 repeated matches, cancellation/eviction, immediate navigation during output, first-frame opening, no resize or agent input, hidden suspension, keyframe focus preservation, read-only ownership, and a narrow field at 2× text. The following continuation keeps retained offline renderers available to Find; never-attached views still need setup guidance.

Native tab hover now hides both adjacent separators, uses a 28-point shape with 12-point corners, and aligns 13-point text with a 10-point close symbol. The title and paragraph layout are cached until the name or selection changes. Before/after native component renders were inspected, alongside an isolated Flutter Find render; neither substitutes for live native interaction or physical-display timing.

## Focus handoff and retained offline views

The reported Cmd+P bug reproduced in isolated tests. Closing the picker could restore the old terminal's FocusNode, whose callback changed the model back to that pane. Both jump and Needs input now clear that restoration before applying the destination. An explicit focus request also reaches an already-selected pane. The canvas reveals the target during the same frame, with a layout correction when a New swarm's full-size content becomes the inset terminal canvas. Ordinary tab switches continue restoring their own saved canvas offsets.

Retained terminals stay mounted while offline, unlinked or temporarily missing from discovery. Their header carries read-only status, so no overlay blocks output or changes terminal dimensions. Cached presentation includes availability and error details; unchanged offline panels can reuse their widget tree too. The optional composer stays mounted and disabled, preserving its unsent draft. Native Find remains enabled for retained buffers. Neither navigation nor unavailable retry attempts discard the session or start a replacement stream.

At this checkpoint the full desktop suite passed 1,039 tests with one skip; the combined suite and isolated render passed 1,040 with one skip. Focus regressions covered repeated and same-Swarm jumps, zoom, offscreen/cross-Swarm targets, the first input frame and unavailable destinations. Offline checks preserved renderer identity, dimensions, selection, scroll, Find and composer text while refusing input. Actual reattachment still replaced the session at this stage; the later reconnect continuation below removes that replacement. These are behavior and frame-order checks, not physical-display latency measurements.

## Native menu update — first pass

History shares the 64-identity session-local navigation record and shows at most 12 recent agents and 12 recent Swarms. Navigation and discovery refresh its lightweight destination snapshots; ordinary terminal notifications reuse them. Unchanged state sends no native update and AppKit retains identical menu items. Menu selection resolves its identity against current open views before focusing, and cannot recreate a closed pane. Cmd+P now has an explicit native menu owner in History, sharing the tested picker handoff. The macOS Settings gear is removed, leaving that space for tabs while keeping Settings in the app menu.

The full desktop suite passes 1,041 tests with one skip; 221 AppKit checks pass, including native menu order, shortcut ownership, stale history actions and modal guards. These checks establish behavior and avoidance of redundant work, not measured native input-to-display latency.

## Reconnect, Chrome History and context cleanup

Explicit reconnect now reuses the session and the mounted terminal view. Keyframes are constructed before publishing their replacement emulator; manual viewport, Find and selection remapping runs only when those contexts exist. The ordinary tail-following path skips the row scan. A generation guard prevents delayed work from an old stream repainting, freezing, clearing an upload or holding up new input. Tests cover late output, blocked old input, old upload completion, closed opening waits and the real keyframe handoff through AppNotifier.

Chrome-style History keeps a separate bounded 128-location Back/Forward trail alongside the existing 64 recent identities and 24 closed-Swarm records. Native sections show 10 closed and 15 visited destinations. Back/Forward changes focus without attachment or network waits; identical menu snapshots retain native item instances. Show Full History reuses the existing immediate search dialog, with a clear session-only scope.

Local Git compatibility reads only bounded metadata files asynchronously, deduplicates pending reads and caches at most 256 folders. Directory events debounce metadata refresh by 100 ms; that delay updates branch context and never gates typing, pane focus or navigation. The permanent wallpaper button and repeated header project text are removed. No additional wallpaper memory or native input-to-display measurement is claimed for this pass.

The full suite passes **1,050 tests with one skip**; hidden AppKit checks pass **229 assertions**. Analyzer output is back to zero errors/warnings and 12 existing vendored infos. The pane header was also rendered with isolated fixtures at three widths. These establish correctness and bounded work, not a measured zero-latency experience. The [prototype review](harness-v2-prototype-review.md) preserves the same constraint for a future Cmd+P preview: bounded retained context, no attachment, network request or transcript scan across the catalog while moving through results.

The Release rebuild succeeded. Live review verified real branch labels, the simplified welcome, Workshop's three-member project association, native History and Back, and Cmd+P → Return focusing an existing local pane followed by a quick return to the original pane. No real-agent input or remote interruption was used for these checks. Native physical input-to-display timing remains unmeasured.

## Native follow-up

The optimized real-data app builds and runs locally. The native tab/canvas polish was visually reviewed before the navigation and retained-canvas continuations; CUA access returned after the pane-focus Release rebuild. The empty wallpaper and tab strip were captured. After the native-menu build, live checks verified File/History, Cmd+P opening, immediate focused search typing and Escape return. At that point no agent views were open, so live terminal destination/input checks remain pending; fake-session regression tests cover them. The tab strip uses AppKit's compact unified title bar: the old right accessory was clipped to 32 points; the container now supplies 40 points and aligns controls with the system traffic lights.

The native check covers overflow, resizing, accessibility order and disabled actions. `bash tool/check_swarm_titlebar.sh /path/to/flutter --window-layout` adds actual container checks in a hidden window at three widths, now for 229 assertions total, including File/History menus, modal/stale-action guards, hover separators and native Find/attention shortcuts. No Flutter engine, account or terminal is accessed.

Wallpaper is built only for the empty New swarm. Populated Swarms paint a flat color matching the selected native tab, and the disposed wallpaper evicts its own decoded cache entry. This removes wallpaper painting/cache retention from the active terminal canvas; no process-memory reduction has been measured yet.

Measure release input-to-display, focus, search, scrolling, layout and tab-switch latency before making user-visible performance claims. The first App Launch Instruments recording overlapped a stale Debug preview and is not a clean baseline. Native end-to-end timings and drag/overflow review remain in the development handoff; passing headless CPU checks does not establish zero latency.
