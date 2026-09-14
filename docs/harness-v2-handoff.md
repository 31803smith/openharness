# Harness v2: goal, plan, and continuation handoff

**Latest continuation checkpoint:** `98fc760` makes New Harness immediately usable
from the keyboard. The folder control receives focus when the dialog mounts;
Enter opens its chooser. A valid keyboard selection focuses the enabled New
Harness action. Cancel/error returns to the chooser, and a pending Codex account
lookup neither focuses a disabled action nor steals focus when it completes.
The next key after successful creation reaches the terminal. **Five current-flow
checks** pass in `/private/tmp/harness-creation-keyboard-after.log` and **29 affected
account/engine/entry checks** pass in `/private/tmp/harness-creation-regressions.log`.
The macOS/Linux keyboard variants are widget checks, not native platform
qualification. Analysis reports no issues in
`/private/tmp/harness-creation-keyboard-analyze.log`.

**Search checkpoints:** `87706a3` fixes command-mode entry from the
collapsed/focused start-page field and keeps its displayed mode synchronized.
`2aaa48a` stops search subscriptions and catalog work while that picker is
dismissed; reopening preserves query/selection and reads current results. Both
are pushed to main. The regressions reproduced incorrect command entry, a catalog
being constructed only to dispose an unused page, and command refreshes after
dismissal. **28 affected checks** pass in `/private/tmp/harness-start-idle-after.log`;
the keyboard host checks also passed in `/private/tmp/harness-inline-commands-after.log`.
The existing guarantee that arrow navigation rebuilds only changed rows remains
verified. Analysis of the five changed source/test files reports no issues in
`/private/tmp/harness-start-search-analyze.log`.

The new Release build succeeds in `/private/tmp/harness-creation-keyboard-release.log`.
Its framework and full bundle signatures verify at
`/private/tmp/harness-pane-controls-release/Build/Products/Release/Harness.app`.
**This newer bundle has not replaced the running preview yet.** Two exact-path
CUA lookups returned `cgWindowNotFound`; the preview process was confirmed running
(PID 92821 at the prior check, recheck before acting). The console again reports
`CGSSessionScreenIsLocked = Yes` after the latest build.
Do not treat that as a stopped app or launch an old fixture. When accessible,
use Quit and Keep Windows, replace only the current checkout's preview with the
verified bundle, and check inline command entry/reopen plus New Harness initial
focus and folder cancellation. The visual and terminal
checks below describe the preceding `b4baf68` preview. Native latency benchmarking
remains deferred.

**Latest UI direction:** [Harness entry and pane controls](harness-agent-first-tabs.md)
is the current contract. **New and Open Harness are separate actions and popups.**
The titlebar has the bell beside the traffic lights and readable New Harness / Open
Harness buttons on the right. There is no floating +. The Google-like New Tab page
is restored, with a solid background matching the selected tab, lower centered
controls and generous whitespace. The blank search field is unfocused initially;
clicking it opens the same results, highlighting, arrow navigation and Enter action
as Cmd-O. The five recent-agent rows are replaced by a small official device photo
and introduction linking to `https://www.autonomous.ai/harness-device`.

Session names sit above **project · branch · machine**, without the repeated
workspace title. Only the highlighted result shows **Open Harness / Open N Harnesses**.
The modal search retains the 90% black backdrop. It has no Commands footer,
creation CTA or “or” divider. Shift-Cmd-P and typing `>` still find commands.
Creation uses **New Harness** for both title and CTA, with no Cancel button.
Escape or one click outside dismisses it without reopening search. The pending
creation receipt and Check status recovery safeguards remain intact.

**Cmd-T = New Tab**, **Cmd-N = New Harness** (creation form), **Cmd-O = Open Harness**,
**Cmd-S = Layout**, **Cmd-H/J/K/L and Cmd-arrows = pane navigation**.
Cmd-1…9 select tabs, Shift-Cmd-arrows move panes, and Shift-Cmd-T reopens closed
work. User overrides retain precedence. File groups tab/harness actions first,
then pane actions. Pin/Unpin and Add Project are absent. Machines follows Models
and starts with **Open Machines Manager**, with a visible **Rename** on each machine.

New Tab remains a useful start page after dismissing a popup. Closing an unused
default-name empty page never adds it to Recently Closed, including pages from
older builds. Closed single-agent harnesses retain their engine icon; groups keep
the group icon.

Terminal scrolling now follows the latest output on new attachment, restored or
reopened work, reconnect, returning to a workspace, reuse of a retained pane,
relayout, resize, zoom and font changes. Regression tests reproduced a retained
pane stuck at its old scroll offset and a late-output/input race 200 lines short
of the bottom. Alignment now resolves against the current buffer during layout.
An additional live Codex failure came from incremental resize repaint: clearing
history briefly reduced the scroll extent to zero, which started a macOS bounce
that kept pulling the viewport up after history returned. The renderer now corrects
the tail **before** publishing content dimensions. Explicit relayout also reaches
unchanged-size neighbors and cancels in-flight scroll animations and dial inertia.
Manual scrollback within an unchanged pane and active Find are preserved; hidden
output still causes no unnecessary frames. Local and remote delayed history,
reconnect and multi-pane transitions are covered with fake sessions.

The current Release preview is built from **`/Users/ab/code/autonomous-harness`**
and running at `desktop/build/macos/Build/Products/Release/Harness.app`.
Build log: `/private/tmp/harness-final-entry-release.log`. The current app framework
and copied bundle signatures verified after refreshing the outer ad-hoc signature.
The prior bundle is preserved at `/private/tmp/harness-before-final-entry-0bmbrwl5/Harness.app`.
Only this checkout's preview was replaced; `/Applications/Harness.app` remains separate.
The other checkout is paused by the user: **do not launch its retired UI**.

Live verification in this exact preview: both idle workshop Codex panes retained
their latest message and prompt across rows → columns → rows → columns, including
the delayed repaint. The app v2 Codex/Claude workspace also retained its bottom
after restoring columns. Both workspaces were left in their original columns.
The start page was visually checked for its continuous background, whitespace,
device photo, absent initial caret, click-to-search, filtering and arrow selection.
The New Harness title/CTA, absence of Cancel, one-click outside dismissal and
separate Open Harness popup were verified live. The start page is left open.

Verification: **35 focused terminal-lifecycle and current-entry checks** pass in
`/private/tmp/harness-tail-and-entry-final.log`, including the macOS incremental
repaint regression and inline search keyboard activation. The other current UI
fixtures passed in `/private/tmp/harness-current-ui-tests.log`; that run's two
ambiguous New Harness button finders were corrected and pass in the final entry
run. **348 AppKit checks** pass in `/private/tmp/harness-header-final-checks.log`.
Static analysis has no errors or warnings and four existing infos in
`/private/tmp/harness-final-entry-analyze.log`. No retired UI or latency benchmark
was exercised.

Publication: the user explicitly requests **frequent commits and pushes**.
`e8960fc` (separate titlebar actions) and `9288ea4` (terminal redraw scrolling) are
pushed to main. The accompanying UI checkpoint contains the revised start page,
shared inline search, device asset and New Harness dialog. The broader goal is
unfinished, and native latency benchmarks remain deferred by user instruction.

Updated September 14, 2026. **Read this first when resuming on another computer.**
This is the current product contract and next-work order. It supersedes conflicting
historical checkpoints in [the progress log](harness-v2-progress.md). The user
requested a portable checkpoint. Continue from the current New/Open design and
the remaining acceptance criteria below; do not restore historical UI to satisfy
obsolete fixtures. The larger performance goal remains unproven, including native
latency, genuine first-use completion and Linux-host qualification.

**Latest priority:** native benchmarking remains explicitly deferred. Continue
current feature, keyboard and usability work. Do not interrupt the user for a
benchmark window or resume calibration merely because the desktop becomes available.

**Current product discussion:** the user reports accumulating live agents after
closing their views. [The lifecycle proposal](harness-agent-lifecycle.md) recommends
explicit Archive/Resume plus bulk cleanup, preserving ordinary view closure.
This is a proposal for discussion, not implemented behavior or authorization to
archive/delete existing user sessions.

Pane headers show only the agent icon and session name on the left. The right
side shows **folder • branch • machine**, replaced on header hover by **Zoom**,
**Delete**, **Close**, with **Keyboard** first for remote sessions. These controls
are small and muted, remain keyboard accessible and reserve the same width as
the metadata. Delete uses the existing confirmation; Close preserves the runtime.
The session tooltip retains full metadata when a narrow header truncates it.
Divider grips are invisible until hover, keyboard focus or resize drag.

Hover near a pane's right or bottom edge to reveal an inset **+** for that
direction. Clicking it opens the shared harness picker, supporting an existing
harness in the chosen position; Cmd-N opens **New Harness** for that split.
Keyboard split commands remain
available. Hover does not change focus or rebuild the terminal; the resize gaps
remain draggable. Controls stay hidden while zoomed or dragging, and a pane too
small for the chosen split explains the required width/height in its tooltip.
The preceding edge-control checkpoint was integrated after the team's agent-first
update on main (`16716d0`). Its twenty-four affected checks passed, with no analyzer errors or warnings. The arm64
Release build was reopened from the exact workspace bundle at the user's request
and confirmed active (PID 18687). Recheck the process before future app actions;
this does not verify native latency. Log: `/private/tmp/harness-split-edges-release.log`.

History recovery also reuses a partially restored swarm: reopening an agent and
then its original swarm adds the missing views to the same tab, retaining newer
choices and live sessions. No runtime cleanup was introduced.

The remote folder chooser now accepts a full path and supports keyboard browsing,
with in-place retry and latest-request ownership. A pending or failed hop cannot
select the previous folder. These changes apply wherever the shared remote
chooser is used: agent working folders, saved projects and profile folders.

[Creation recovery](harness-agent-creation.md) now distinguishes a delayed reply
from a refused launch. The form retains its choices and offers **Check status**
after a timeout/disconnect. That action only reads the original creation receipt;
it never creates another agent. A confirmed agent returns to the original swarm
or stays discoverable in Add if that destination changed. Older CLIs can still
create normally, but cannot recover a lost result through this new status RPC.
Form intents currently last for that open dialog; do not claim app-restart recovery.
New and Open Harness now have separate entry points. Cmd-N while search is open
closes it before opening creation and retains the original swarm/split destination.
A closed swarm or changed split gets an explanation instead of redirecting the
addition. A background empty tab cannot take focus from the open creation dialog.
Outside click and Escape dismiss the form directly; no picker is restored and no
Back to Search or Cancel action is shown. Uncertain requests retain Check status
and Close. There is no multi-select or checked-agent draft, and creation intent
recovery still lasts only for that open dialog.

Browser sign-in now offers **Open browser**, **Copy link** and immediate **Cancel**
while waiting for authorization. Reopening uses the current link without starting
another CLI login. Cancel works even before the CLI finishes starting; late URLs,
results and browser replies cannot affect a replacement attempt. After browser
authorization succeeds, those controls disappear while the workspace restores.
Enter starts sign-in and can start again after cancellation. Live first-install
and provider sign-in still need direct observation.

Repository cloning now treats **Escape** as Cancel, waits visibly for cleanup,
and does not advance onboarding if a cancelled clone finishes successfully.
Failures retain the URL and destination, reveal the error even with large text,
and return keyboard focus to the retry action. The public GitHub clone service
was also exercised directly in a disposable folder; private access and the
native chooser still need first-use observation.

First-launch installation now keeps **Install**, **Retry** and **Check again**
visible while the tool list and diagnostics scroll. Enter activates the current
step, including recovery after failure; explicit manual/detail focus is retained.
Manual Retry performs a read-only check instead of silently doing nothing.
Verbose output is optional under **Setup details**, with Copy diagnostics still
available. This changes the first-launch tools screen before sign-in; it does not
add another step to New agent or the common empty-swarm page.

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
- Continue on **`main`**, tracking `origin/main`. The user's latest instruction
  is to work, commit, and push directly on main from now on. This supersedes
  the earlier preference for creating a fresh feature branch after each merge.
- Historical Add-to-New-agent return checkpoint, superseded by the explicit
  Back to Search and single-dismissal behavior above: 76 affected workflow checks and one
  real-font render check (77 total). Nine new checks cover cancel/Escape,
  successful and uncertain creation, checked agents, changed targets and draft
  revalidation. The three cancellation regressions failed before the fix. The
  existing split check now verifies both return to Add and the next terminal
  key after dismissing Add. Analysis has zero errors/warnings and 14 existing
  infos. Logs: `/private/tmp/harness-add-return-final-{tests,analyze}.log`.
  The isolated minimum-size/2× text renders preserve the returned selection and
  preview. Shift-Enter passes through the production Dart keyboard dispatcher
  in those fixtures; that is not direct verification of the user's native issue.
  The normal arm64 Release build succeeds at
  `/private/tmp/harness-add-return-release/Build/Products/Release/Harness.app`;
  log: `/private/tmp/harness-add-return-release.log`. It was not launched and no
  real agent was created/stopped. Benchmarking stays deferred.
- **`3ab66ca`** fixes first-launch installation, passing 59 affected workflow checks and one real-font
  render check (60 total). Six new regressions cover minimum-size/2× text action
  visibility, Enter/retry, manual-mode focus and read-only retry, and diagnostics.
  The original action-visibility and Enter regressions failed before the fix.
  Analysis has zero errors/warnings and 14 existing infos. The normal arm64
  Release build succeeds at
  `/private/tmp/harness-setup-release/Build/Products/Release/Harness.app`.
  Logs: `/private/tmp/harness-setup-final-{tests,analyze}.log` and
  `/private/tmp/harness-setup-release.log`. The app was not launched. These are
  fake-provisioner and rendered-screen checks, not a real fresh install or
  provider sign-in. Main was fast-forwarded through the team's `e14d0fb`;
  incoming release-script and dial-firmware changes leave the tested desktop
  application sources unchanged. Benchmarking remains deferred.
- **`cb92d2a`** adds clone recovery, passing 49 affected workflow checks and one real-font render
  check at 880×560 with normal/2× text. The original cancellation and keyboard
  retry regressions failed before the fix; visual review then exposed the hidden
  large-text error. Analysis has zero errors/warnings and 14 existing infos.
  The normal arm64 Release build succeeds at
  `/private/tmp/harness-clone-release/Build/Products/Release/Harness.app` and was
  not launched. Logs: `/private/tmp/harness-clone-{final-tests,final-analyze,release}.log`.
  A real public `octocat/Hello-World` clone passed with isolated Git configuration,
  a valid checkout and no staging residue; its temporary folder was removed.
  Log: `/private/tmp/harness-clone-public.log`. No user agent or running app was
  started/stopped, and no benchmark ran.
- **`b7b6075`** adds browser-sign-in recovery and passes 64 affected workflow checks
  plus one real-font render check (65 total), including late process startup,
  cancelled/replaced sign-ins, browser launch failure, clipboard recovery,
  keyboard retry and the authorization-to-workspace boundary. Analysis has zero
  errors/warnings and 14 existing infos. Minimum-size and 2× text renders were
  reviewed. Logs: `/private/tmp/harness-signin-final-{tests,analyze}.log`.
  The normal arm64 Release build succeeds at
  `/private/tmp/harness-signin-release/Build/Products/Release/Harness.app`;
  log: `/private/tmp/harness-signin-release.log`. It was not launched. The team's
  `b45c156` CLI recap change was fast-forwarded from main and does not overlap
  this desktop work. No real sign-in, agent restart or benchmark ran.
- The creation-to-Add continuation passes 87 affected workflow tests, including
  six new keyboard/destination regressions, plus a real-font render check at
  880×560 with normal and 2× text. Analysis has zero errors/warnings and the same
  14 existing infos. The team's already-merged recap change (`fd02a15`, PR #38)
  was fast-forwarded without touching teammate branches; its CLI files do not
  overlap this desktop work. Logs: `/private/tmp/harness-find-created-{workflows,final-recovery,analyze}.log`.
  The normal arm64 Release build succeeds at
  `/private/tmp/harness-find-created-release/Build/Products/Release/Harness.app`;
  log: `/private/tmp/harness-find-created-release.log`. It was not launched or
  used for a benchmark.
- **`3585051`** records CLI creation receipts and encrypted status recovery.
  **`7ae2cba`** preserves the team's main through PR #37 (`012c171`, Option-Enter
  inserts a line break). **`c3db329`** keeps unknown
  outcomes on Check status, preserves the original destination and counts a
  recovered creation once. The affected desktop checks include that incoming
  terminal change: 127 checks pass, plus one real-font render check. Analysis
  has zero errors/warnings and 14 existing infos. The normal arm64 Release
  build succeeds at `/private/tmp/harness-creation-release/Build/Products/Release/Harness.app`;
  it was not launched. CLI typechecking, bundling and 150 related checks pass.
- **`e73eb6e`** adds keyboard remote-folder selection and reliable asynchronous
  browsing. The affected workflow/render checks (58 total), analysis and normal
  Release build pass. **`8800c35`** preserves the team's concurrent main through
  `e094271`; those incoming CLI/device changes leave the tested desktop tree
  unchanged. No teammate branch was merged separately.
- **`d727360`** clarifies view removal and restores closed work into its existing
  swarm. **`332546f`** keeps terminal relayout from taking keyboard focus from
  resize controls. **`eef17f6`** preserves the team's `e68c893` local-machine
  default for general New agent actions; explicit split context stays intact.
  The combined desktop suite passes 1,317 tests, one skip.
- **`339f008`** saves the opening continuation: it keeps the retained canvas
  built while a picker opens/closes and shares validated catalogs across openings. Warm Add
  opening measured 22.006 ms median versus 26.273 ms in the same headless
  fixture; cold starts and native display latency are not established by it.
  Main includes the team's independent device change `5f8baac`. The complete
  desktop suite passes 1,309 tests with one existing skip.
- **`3a7fe57`** preserves the team's `51c0d27` titlebar Settings-button removal.
  The combined desktop passes the same 1,309 tests, 51 native decoder checks,
  347 AppKit assertions, analysis and a Release build. Settings remains in the
  app menu/keyboard flow. **`51f62e7`** then preserves the team's independent
  device-only changes through `22653fe`; desktop sources are unchanged.
- **`e71e0ca`** saves Add's frame continuation: it reuses unchanged result rows
  and keeps background pane additions from taking the picker's Flutter focus.
  The full suite passes 1,302 tests. Native fixture identity repair is saved in
  `fe42f2e`; `56f9d2a`
  preserves the team's subsequent `9e2e4be` branding/update work.
  **`56143bd`** integrates the team's later `cdb876e` removal of the obsolete
  internal-V2 update flag. The combined suite still passes all 1,302 tests with
  one skip; analysis remains at zero errors/warnings and 14 existing infos.
- **`5f3ecae`** saves Cmd-N Add, the prominent New agent button, optional
  multi-select, visible machine/project starters and the larger floating-button
  inset. **`f514140`** preserves the team's concurrent main through `76a469b`,
  including its Settings toolbar button, terminal color schemes, dial work,
  error messages and public bundle-name cleanup. No teammate branch was merged
  separately or retired.
- Only consolidate this user's own branches and PRs. The authenticated account
  is `deehw`, matching this session's commits and PRs #31/#34. The user explicitly
  excluded other team members' branches from merging or retirement. The audit
  found no remaining remote commit by this session's author outside main and
  no other open PR by this account. Teammates' branches and PR #28 remain untouched.
- [PR #34 — Separate navigation from adding agents and simplify first use](https://github.com/autonomous-ai/autonomous-harness/pull/34)
  is **merged**, with all six continuation commits preserved by `ccd1f35`.
  `fd3ced0` also preserves the team's concurrent main update `4b2f783` and was
  pushed successfully. `swarm-onboarding` was then deleted remotely with an
  exact-tip lease and locally with the merged-branch check. Do not recreate it.
- This repository consolidation does not qualify the desktop for release.
  Native responsiveness, first-install behavior, and remote/platform checks
  below remain unfinished.
- [PR #31 — Harness: swarm workspaces for AI agents](https://github.com/autonomous-ai/autonomous-harness/pull/31)
  merged at `cb24361` on September 14, 2026 (02:56 UTC), with `744c1fe` as its
  app-v2 head. Its merge did **not** include the later Navigate/Add commits.
  This was verified from GitHub's merge metadata and the fetched main history.
- Previous UI checkpoint: `ac443eb`, following `2e8d69d` (search/menu controls),
  `4154cf6` (Harness branding/account labels), and `06ba77c` (agent creation).
- Previous code checkpoint: **`26a372e`**, terminal viewport preservation and naming
  an empty default swarm after its first agent.
- `744c1fe` saved the portable handoff, pending UI drafts, native benchmark
  tooling, and collaboration design notes.
- **`2d3c024`** implements distinct Navigate/Add experiences,
  consistent empty-swarm starters, command-mode focus preservation, and the
  navigation catalog performance improvement described below.
- **`e122b63`** saves the common empty-swarm start page, folder/clone entry points,
  loading/focus recovery and simplified single-local-machine form.
- **`a2888ef`** carries `2d3c024`, `ed9151a` and `e122b63` onto the fresh branch
  without rewriting them, preserving newer main changes including device focus.
- The user explicitly authorized frequent public repository checkpoints.
  The earlier continuation preserved every app-v2 commit before app-v2 was
  deleted remotely with an exact-tip lease and then locally. Do not recreate it.

Start with a clean checkout of main and inspect its latest commit.
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
- Reopening a swarm that was already partially restored returns to that same
  identity and adds its missing views. Preserve its newer name, focus, pins and
  presets. If all missing views cannot fit, retain the closure for later without
  duplicating a tab, adding a subset, or evicting existing agents.
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
| Bottom-right floating + or Cmd-N | Add to this swarm | The same Add agent experience as New swarm. |
| Pane menu: Split right / Split down | Add at this position | The same Add agent experience, preserving the selected neighbor and direction. |
| New agent action, including Shift-Cmd-N | Create | Always create a fresh runtime in the intended swarm/position. |
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
- Each swarm is one selectable top-level row, with its agents indented below.
  Do not repeat the swarm as a heading plus a child result. Empty swarms appear
  once. Agent-only searches retain the parent while selecting the best matching
  agent for Enter.
- Cmd-P remains the navigation shortcut. Cmd-Shift-P remains command mode.
  Native menu, tooltip, help, custom bindings, and actual dispatch must agree.
- Agents with no open swarm belong to Add. Navigate's explicit “Add an agent…”
  action opens that separate surface while preserving the query. Closed work
  remains in History. A missing/stale navigation location never redirects to
  another swarm or changes membership.
- Entering/leaving `>` command mode keeps the same text editor mounted, so the
  immediately following select-all/delete or typing event keeps its focus.

### Add agent

- Latest user decision: **start immediately with the first agent**. Search +
  Enter or a welcome suggestion opens it directly. Keep “Add your first agent”
  above the choices; no draft-list or Create swarm step. Machines and projects
  stay visible as one-click swarm starters. This supersedes the briefly proposed
  mandatory assembly step.
- Multi-select is optional in Add: check rows or use Shift+Enter, retain the
  selection across queries, remove selections in the visible strip, then use
  Add N agents. Default click/Enter still adds one immediately. A split chooses
  one agent for its specific position. New agent remains the fresh-runtime path.
- Cmd-N opens Add; Shift-Cmd-N opens the fresh New agent form. This latest
  user choice supersedes the old Cmd-N creation default. New agent must be a
  large filled button beside the search field, not a small footer action. Only
  the highlighted result shows the action label and Enter hint at its right
  edge; do not repeat it on every row.
- The bottom-right + floats over the terminal canvas, inset 28px from the right
  and bottom edges. Do not reserve a footer or shorten every pane to make room
  for it.
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

**Implemented on main:** swarm/session retention, native tabs, layouts,
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
agent. Machines and projects are visible as one-click swarm starters; the
first agent opens immediately and optional multi-select lives in shared Add.
A single usable local computer no longer needs a Machine dropdown
in the creation form. Failed agent checks now offer **Retry** in place, preserving
the folder, chosen agent and permission setting; recovered Codex profile support
loads into the same form. A late check for a different machine cannot change the
current choice. Delayed discovery enables Enter on the primary action
without stealing an explicit focus choice. Offline/linking cases expose their
next action. Large text stacks the layout, and New agent now uses the shared
darker modal veil. See [first-use details](harness-v2-appearance-onboarding.md).
Observed first-install/provider flows and onboarding conversion/time remain
unverified; do not infer them from these UI changes.

**Remote folder selection:** the chosen machine is named above an editable path.
Enter opens that path; Down enters the folder list, arrows move, Enter opens a
folder, Alt-Up goes to its parent, and Cmd-Enter (Ctrl-Enter on other platforms)
selects the loaded folder. Home and Retry recover from inaccessible paths.
Delayed replies cannot replace a newer request, path draft or composition.
Failures retain the last usable listing and identify which directory it shows.
Folder selection returns to the same New agent choices and starts no agent.

**Archived drafts:** both are superseded. The onboarding ideas were adapted into
the common page, without adding another first-tab-only component.

**Latest verification:** the remote-folder continuation passes 57 affected
workflow checks, including nine new folder regressions, plus a real-font render
check at 880×560 with normal and 2× text (58 total). Analysis reports no errors
or warnings and the same 14 existing informational diagnostics. Logs:
`/private/tmp/harness-remote-folder-{final-tests,final-analyze}.log`.
The normal macOS Release build also succeeds with `FLUTTER_TARGET=lib/main.dart`:
`/private/tmp/harness-remote-folder-release/Build/Products/Release/Harness.app`;
log: `/private/tmp/harness-remote-folder-release.log`. The running app was not
replaced or restarted.
The tested folder replies and creation calls are isolated fixtures; no real
agent was started or given input. Live remote and first-install qualification
remain outstanding, and benchmarking remains deferred.

**Previous verification:** the History recovery and viewport-focus continuation,
including the team's default-machine update in `eef17f6`, passes **1,317 desktop
tests**, one existing skip. The analyzer reports
zero errors/warnings and the same 14 informational diagnostics. The isolated
AppKit titlebar/menu fixture passes 335 checks, including hidden window layout.
Logs: `/private/tmp/harness-reopen-existing-final-full-tests.log`,
`/private/tmp/harness-reopen-existing-final-analyze.log` and
`/private/tmp/harness-reopen-existing-native.log`. The 54 focused History checks
and 23 focused terminal/recovery checks also pass. A subsequent normal macOS
Release build from `3a4ae22` succeeds with `FLUTTER_TARGET=lib/main.dart` at
`/private/tmp/harness-recovery-release/Build/Products/Release/Harness.app`;
log: `/private/tmp/harness-recovery-release.log`. The bundle is named Harness
with identifier `ai.autonomous.harness`. No real agent received test input;
the running preview was not replaced or restarted. Live native workflow
verification remains outstanding and benchmarking remains deferred.

The full suite caught viewport refresh taking focus from a resize handle. The
fix keeps geometry updates from claiming keyboard ownership; pointer Escape,
repeated resize arrow keys, and latest-output positioning across a real layout
change are verified together.

**Previous verification:** the first-agent Retry continuation, including the team's
`5f279e1` pane-menu Delete action, passes 1,311 desktop tests with one existing skip.
Main subsequently fast-forwarded through the team's independent socket, terminal,
titlebar and device changes at `87f8fcd`; the results below describe the tested
`5f279e1` base plus this Retry change, not a rerun of that later integration.
Analyzer reports zero errors/warnings and 14 existing informational diagnostics
(12 vendored, two inherited from main). Logs:
`/private/tmp/harness-agent-check-retry-{full-tests,integrated-analyze}.log`.
The macOS arm64 Release build succeeds with `FLUTTER_TARGET=lib/main.dart`
in a separate output directory, `/private/tmp/harness-agent-check-retry-release`;
log: `/private/tmp/harness-agent-check-retry-release.log`. The running app was not
restarted, so do not claim its process has loaded these source changes.
The preceding combined titlebar/picker source passed 51 native keymap decoder
and 347 AppKit assertions, including the exported Dart keymap and hidden window
layout. Native log: `/private/tmp/harness-add-open-titlebar-native.log`.
The preceding Add/shortcut integrated
macOS arm64 Release build succeeded with
`FLUTTER_TARGET=lib/main.dart`. Synthetic real-font captures of the visible
starters, Add, multi-select and Navigate were reviewed at 1280×800 and 880×560
with 2× text. These do not measure native display latency or real reconnect.
Integrated test/native/analysis/build logs:
`/private/tmp/harness-revised-add-integrated-{tests,analyze,native,build}.log`.
The integrated Release build uses the new `ai.autonomous.harness` bundle ID.
Add's new full-frame fixture observes an arrow-selection median of 4.714 ms
versus 8.592 ms before the change, with 2,000 agents and five retained terminals.
Opening did not improve. This is headless debug CPU time, not displayed latency.
The next paired opening pass reuses unchanged catalogs and removes redundant
canvas builds: warm opening median is 22.006 ms versus 26.273 ms. Query timing
was worse in that run. Reopening refreshes output and revalidates metadata and
membership without retaining canceled queries/selections. See the current
performance table before making a broader speed claim.
Navigate/Add timings and their exact scope are in
[the performance record](harness-v2-performance.md). The new navigation catalog
build measured 0.188 ms median / 0.259 ms p95 in the earlier integrated run for
50 locations across 12 swarms. Add's 2,000-agent query measured 0.959 ms median /
1.005 ms p95. The five benchmark cases passed; native event-to-display remains
unmeasured. Log: `/private/tmp/harness-onboarding-main-benchmark.log`.

**Also saved:** [native benchmark tooling](../desktop/tool/native_benchmark/README.md)
and [shared-swarm collaboration research](harness-collaboration-design.md), which
were existing uncommitted work. Collaboration is a separate proposal/prototype,
not implemented multiplayer or a prerequisite for finishing this desktop pass.
The benchmark accepts the team's current public bundle ID while still producing
a distinct Harness Benchmark app. Nine isolated Python checks pass. Preflight
distinguishes installed copies from workspace builds by exact location as well
as identity. Preserve its isolation and foreground/key-window guards. The
performance notes explain the earlier failed calibration; these tooling fixes
provide no new latency measurements. The most recent disposable Release build
is `/private/tmp/harness-native-benchmark-v99tt1m2`, pinned to production source
`a6fe4a4`, including the later titlebar change. Its bundle identity is
`ai.autonomous.harness.benchmark`; receipt:
`/private/tmp/harness-native-approved-prepare.log`. It was not launched: the
desktop was locked, and the user then deferred benchmarking to focus on
features. Both Harness processes remained running. Rebuild from current source
when measurement returns to scope. The [performance record](harness-v2-performance.md)
retains the earlier fixtures and artifacts.

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

The `swarm-onboarding` continuation's macOS arm64 **Release build succeeded**
after integration with updated main,
with `FLUTTER_TARGET=lib/main.dart`. Log:
`/private/tmp/harness-onboarding-main-release-build.log`. Computer Use still returns
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

1. **Continue from current main and the contract at the top of this file.**
   The latest start page, separate New/Open popups and terminal relayout fix were
   verified in this checkout's Release preview. Historical progress entries and
   saved preview bundles are not the current UI. Preserve running agents and
   input during targeted native verification; do not relaunch just to reconfirm
   unchanged menus. Commit and push verified work frequently.
2. **Complete the current keyboard and first-use paths.** Exercise the initially
   unfocused start-page field, collapsed/expanded search, command-mode entry,
   composition, keyboard selection and the first key after activation. Check
   live discovery while reading results and avoid work for dismissed surfaces.
   Observe fresh dependencies, provider sign-in, cloning, first task and opening
   a second harness; record actual steps/errors to a usable agent. Preserve
   choices on failure and the separate New Harness and Open Harness intentions.
   Browser reopen/copy/cancel recovery is implemented with isolated subprocess
   and platform fixtures. Check the real browser handoff and provider return;
   do not infer live sign-in success from fixture results.
   Public GitHub cloning passed a direct service check in a disposable folder;
   the native chooser and private repository access still need observation.
   Creation recovery is implemented and tested with isolated replies. Verify a
   deliberately delayed remote create on a disposable agent, including an older
   CLI and a changed original swarm. A status check must remain read-only. A
   durable desktop pending-creations list and crash-window registry reconciliation
   are still future work; the current dialog cannot resume its intent after closure.
   The start page and Open popup share input/results components. New Harness
   opens its own creation form. Outside-click/Escape dismisses creation completely;
   no Back to Search, Cancel, floating +, Commands footer or multi-select returns.
3. **Recheck fresh terminal positioning and real workflows** on disposable
   local/remote agents: startup, delayed snapshots, resizing, returning to a
   scrolled view, reconnect, paste, selection, and IME.
4. **Deferred: measure native responsiveness** under representative retained/output load,
   using the repaired benchmark identity checks for the team's new
   `ai.autonomous.harness` macOS bundle identifier (Linux now uses
   `com.autonomous.harness` and executable `harness`). Nine isolation tests pass;
   a fresh disposable Release fixture is available at
   `/private/tmp/harness-native-benchmark-v99tt1m2` from source `a6fe4a4`,
   including the team's later titlebar change. The user explicitly answered
   **“Run it now”** and authorized briefly quitting/reopening the workspace
   preview while leaving installed Harness and underlying agents running.
   Do not ask for that approval again. The attempted UI access returned
   `cgWindowNotFound`; a read-only console check confirmed the Mac is locked
   (`CGSSessionScreenIsLocked = Yes`). Neither Harness process was stopped and
   the benchmark was not launched. The user then said to do the benchmark later
   and focus on building features. Keep it deferred. When measurement is back
   in scope, use an unlocked desktop, normally close the exact workspace
   preview, accept calibration only with the active/key-window guards passing,
   and reopen the preview even if calibration fails. No native samples have been
   accepted. See the current performance record for exact artifacts.
   Then close remaining visual/platform/release qualification gaps. Maintain
   the main-branch handoff and keep it honest about what's still unverified.

## Acceptance criteria

### Navigation and adding

- Cmd-T opens the current start page; Cmd-N opens New Harness and Cmd-O opens
  existing-work search. Explicit titlebar buttons perform those same actions.
- Open Harness and the inline field share result rendering, filtering, arrow
  selection and Enter behavior. Ordinary search opens the chosen existing
  session in the captured workspace; navigation/history chooses its destination.
- The first character typed after navigation reaches only the selected agent.
  Hidden/offscreen/zoomed destinations are revealed while retained sessions and
  sessions survive switching away and back. Returning reveals the latest output.
- Reopening one agent followed by its original swarm restores a single workspace
  with shared sessions, including at the tab limit. A full destination preserves
  its recovery entry until the entire missing membership can fit.
- New and Open have separate popups. Both split directions preserve their exact
  original placement, including Cmd-N from an active split picker. Source swarms
  remain intact, and opening an existing agent starts no duplicate runtime.
- Already-present, offline, removed, changed-membership, full-capacity, canceled,
  and failed asynchronous actions produce a clear result without modifying the
  wrong swarm or losing a draft. Late completion revalidates its destination.
- Arrow keys, Enter, Escape, Cmd-A/Delete, paste, and IME work in each input.
  One selected result drives the preview; repeated output cannot steal focus.
- Notifications sits beside the traffic lights. The tab-strip + opens New Tab;
  New Harness and Open Harness are explicit buttons on the right. No floating +.
- Search results show a prominent session title over project · branch · machine.
  Only the selected row shows Open Harness / Open N Harnesses or the split action.
  The popup has a dark backdrop and no footer or creation CTA. The start-page
  dropdown uses the same rows and remains usable at small and large window sizes.

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

- Fresh and revisited views land at the latest output, including tall/delayed
  snapshots, incremental resize redraws and multi-agent workspaces. Manual
  scrollback within an unchanged pane and active Find retain their chosen position.
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
  Full desktop regressions must pass before declaring the desktop release ready.
- Verify macOS native behavior directly and qualify Linux on a Linux host.
  Windows support is unexercised; do not claim it from macOS test success.

## Implementation and verification map

| Area | Start here |
| --- | --- |
| Workspace orchestration, picker routes, split/new-agent context | `desktop/lib/screens/swarm_screen.dart` |
| Shared remote folder browsing and request ownership | `desktop/lib/widgets/remote_folder_picker.dart`, `desktop/test/remote_folder_picker_test.dart` |
| Search data, actions, destinations | `desktop/lib/state/swarm_search.dart`, `swarm_navigation.dart`, `swarm_catalog.dart` |
| Start page, Open/split search and separate creation | `desktop/lib/widgets/harness_start_page.dart`, `swarm_switcher.dart`, `swarm_search_input.dart`, `new_agent_dialog.dart` |
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
is **Harness**. Main now uses `ai.autonomous.harness`; older running previews may
still report `ai.autonomous.harness.v2`. Do not infer the exact running process
or its state from the current on-disk bundle. Workspace Release path here is
`desktop/build/macos/Build/Products/Release/Harness.app`; the installed Harness
was a separate process. Recheck exact bundle paths/PIDs before normally quitting
or relaunching a preview. Do not launch a competing duplicate or use a real
agent's prompt as a test input.

Keep tests/benchmarks isolated with temporary stores and synthetic/disposable
transports. Do not upgrade or restart the user's production CLI/daemon for
qualification. Commit and push directly to main using ordinary fast-forward
pushes. If the team advances main, fetch and integrate their commits without
rewriting published history. Publishing a release and production end-to-end
operations are separate tasks. Keep handoff notes current as work progresses.
