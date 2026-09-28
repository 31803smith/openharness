# Phone app, overnight 2026-09-27 → 28

The goal set at bedtime was to make the Harness phone app world class. That meant:
- test coverage and edge cases;
- fixing the bugs found;
- improving the UI/UX;
- a panel of AI users playing the target audience, whose feedback drives the fine-tuning.

That audience is people with strong consumer-app taste who now run Claude Code and Codex and want to manage them from a phone.

Everything below is on branch `phone-overnight-polish` (pushed to origin). Nothing was merged or released overnight. **The last section is the handoff for the next agent.**

## In one screen

- **Tests:** 486 → 1,555 (plus 25 skipped). The whole suite passes. `flutter analyze` is clean outside `third_party/`.
- **Coverage:** 50.4% → **87.0%** of lines, not counting `third_party/`.

  | Area | Coverage |
  |---|---|
  | e2ee, api, auth, notify, theme | 100% |
  | viewer | 99.2% |
  | p2p | 98.5% |
  | core | 97.2% |
  | usage | 95.0% |
  | ws | 93.1% |
  | analytics | 92.1% |
  | widgets | 89.8% |
  | phone | 89.0% |
  | shared | 81.2% |
  | state | 80.3% |
  | demo | 77.0% |
  | terminal | 74.9% |
  | logging | 72.6% |
  | settings | 46.2% |
  | clipboard | 33.3% |

- **Dead code:**
  - 52 files and about 17,100 lines the phone never runs were deleted. Each deletion was proved with tree-shaken AOT builds for iOS and Android.
  - The desktop's half of `AppNotifier` was cut: 7,100 more lines, 13 files. `viewer` is now non-nullable.
- **Bugs:** 38 real bugs fixed, each with a regression test (listed below).
- **Test safety:** every test now runs in a throwaway home (`test/flutter_test_config.dart`), so no test can read or write a developer's `~/.harness`. `test/test_home_guard_test.dart` pins this.
- **Review panel:** five AI personas, two rounds. The average score went from 6/10 to 7/10. The round 2 fixes landed after scoring; round 3 has not run yet.

## The review panel

Five personas each reviewed renders of every phone screen. In round 2 they also saw an 18-screen walk-through of the real app, recorded on the iOS simulator in sample mode.

| Persona | Lens | Round 1 | Round 2 |
|---|---|---|---|
| Maya | design lead on two iconic consumer apps | 6 | 7 |
| Theo | founder of a Things/Superhuman/Linear-style productivity app | 6 | – |
| Priya | runs 6–10 Claude Code and Codex harnesses across three machines | 6 | 7 |
| Sam | first-time user with consumer taste; Claude Code on the Mac, no Harness | 6 | 7 |
| Jordan | former Apple Design Award juror (HIG, accessibility) | 6 | 7 |

### Round 1 findings that all five agreed on, and what happened

| Finding | Outcome |
|---|---|
| The terminal is clipped at the right edge (a blocker, 5/5) | **A fixture bug, not the app.** The render test seeded a 46-column screen into a 42-column view. Fixed the fixture; the simulator walk-through confirms the live app fits. |
| The mic covers the agent's input line | **Kept.** Your decision: "the current mic location is perfect". |
| Voice sends words you never saw | **Kept.** Your decision: auto-send. |
| "Harness" confuses as a noun | **Kept.** A harness is a session: one agent, many harnesses. It is now taught where it is first met: New ("A harness is one session of an agent"), How Harness works, and the "N harnesses" count. |
| Every other computer needs its own password | **Fixed.** A locked computer unlocks by scanning its Add Phone QR; the password stays as the fallback for servers. |
| Two different set-up screens | **Fixed.** There is one set-up page (the website's download menu). Signed in, it also watches for the computer and pairs by scan. |
| Settings duplicates and unclear labels | **Fixed:** "Phone name", "App colors", the lone "usage" header removed, readable heading contrast. |
| VoiceOver can't read the terminal or reach Find or New | **Fixed.** |
| The scroll-position tag "[22/39]" is jargon | **Removed.** Your call: "we don't need the scrolling indicator". |

### Round 2 fixes

- **The sample.** Its agents stopped parroting your words back ("On it — run the tests…"). This matters because the "how it works" video is recorded from the sample. It also announces permissions the way the daemon does ("Approve Bash command: psql …") rather than "Do you want to proceed?", and names its computer "studio" rather than the fixture id "sample-studio".
- **The line above the mic** hides while you read history; it used to print over the rows being read.
- **The key strip** opens on its own keys. It used to scroll to the agent's `shift+tab` hint on every open, which pushed **esc** off the edge while the agent said "esc to interrupt".
- **VoiceOver:** it can cancel a voice take, hears "Asking: …" when a question opens, and reads the line above the mic as a live region.
- **Copy:** "5 harnesses", "Leave the sample" (both places), "Choose an agent and a project".
- **The scan page** says the link is end-to-end encrypted, which was the first-time user's trust gap.
- **New** shows branch, approvals and profile all the time. The `[+]` toggle is gone; it hid the two things worth checking before a harness starts, over an empty half-screen.
- **Settings:** Usage, Computers and Phone name join the account group. There is no lone Usage card, and Phone name is no longer filed under *terminal*.
- **"Stop this harness…"** stays small at the foot of the menu but is now red; faint grey read as disabled.
- **Form rows** put the label on the value's first line; "approvals" used to sit beside its note.

## Bugs fixed (each with a regression test)

**Sign-in and pairing**
- A scanned pairing code no longer outlives its session.
- A refresh in flight cannot bring back a signed-out session.
- A rate-limited refresh no longer signs the phone out.
- No sign-out from a closed socket, and no hot loop on a refused token.
- Linking never throws, so Unlock and Pairing cannot hang for good.
- Pairing times out on a dial that never opens, and keeps a lockout's retry time.
- A scanned code whose account cannot be read no longer hangs on "Pairing…".
- Pairing by password names this phone to the computer (it was "harness link").

**Connection**
- A replaced relay connection can no longer speak for its machine.
- A replayed welcome or rekey cannot roll the group key back.
- A data channel closing under an open link no longer throws uncaught.
- A second `terminal_ready` for one open no longer leaks a heartbeat.
- A locked state file no longer stops a machine reconnecting for good.
- A terminal switched off by an unanswered negotiation is asked about again.

**Terminal and Focus**
- The terminal follows a keyframe that swaps its screen, not only a rebuild from above.
- A pager guess reopened after its stream died no longer takes the terminal.
- A tap reopens a dead stream.
- The kept screen of an agent read a moment ago is shown, not a blank page.
- A conversation open in a terminal is refused in words, not as a lost reply.
- A question's refusal of a voice answer says why, not "terminal not taking input".
- A resume the machine never received is sent again, not checked forever.
- A stopped harness stays on the phone; the minute's sync sees every field it draws.

**Layout**
- An emoji where a name is cut no longer crashes Focus or Settings.
- The Focus title and the sample's end card no longer overflow at large text.
- The welcome screen and pairing scroll instead of overflowing.
- New's dock scrolls instead of overflowing on a small phone.
- The attaching skeleton shows with Reduce Motion on.

**Dialogs**
- A field inside an app dialog gets the focus it asks for, and the keyboard.
- A rename answer landing as the dialog closes no longer pops the page under it.

**Usage and notifications**
- A reset time past what a DateTime holds no longer drops a machine's usage.
- A partial or failed usage cycle keeps the figures it could not renew.
- One failed start of the notification plugin no longer silences the launch.
- A notification body is never cut through the middle of an emoji.

**Privacy and logs**
- The debug log keeps the length of a harness's first task and a Find search, never the words.
- Log redaction blanks plain-base64 bearer tokens, Basic auth and sign-in codes in URLs.
- An analytics event trimmed while on the wire no longer takes the next one with it.
- A busy analytics visit keeps `analytics.json` within a minute of the clock.

## Decisions already made by the user (do not re-propose)

- Voice keeps auto-send.
- The mic stays where it is; the terminal is full screen under it.
- Keep the word "harness" (harness = session; one agent, many harnesses). Teaching it is fine; renaming it is not.
- No scroll-position indicator. The "api-fix asking" label stays.
- PRs only. The user merges and releases; nothing is merged or released without their explicit word.

## Handoff for the next agent

### State

- Branch `phone-overnight-polish`, pushed. It is 113 commits ahead of `main`. **No PR is open yet**; opening one is the next step (the user merges).
- Merged into it and finished: `coverage-rest` (coverage engineer), `desktop-cut` (the desktop's half of the notifier), and the phone-screens and state-core engineers' passes. No engineer is still running.
- Never commit `mobile/ios/Runner.xcodeproj/project.pbxproj`. It carries the local signing team and stays modified in the worktree.

### How to run

From `mobile/`, with Flutter 3.47.2:

- **Everything:** `flutter test`, about one minute. For coverage, `flutter test --coverage`, then read `coverage/lcov.info`.
- **Screen renders:** `PHONE_RENDER_DIR=<dir> flutter test test/render/phone_screens_render_test.dart`. It writes 25 PNGs, one per screen. The fixture terminal is 42 columns, so canned lines must fit in 42.
- **Walk-through on the iOS simulator, sample mode only:** `HARNESS_JOURNEY_OUT=<dir> flutter drive --driver=test_driver/journey_driver.dart --target=integration_test/tour_test.dart`.

### Rules

- **No real account, device or daemon from any automated or AI-driven input.** Personas and engineers drive only sample mode, renders and the simulator in sample mode.
  - No test may use the network.
  - Engineers do not push; the lead merges their branches.
- Unset `TMUX` in tests.
- Every git and gh action is done as `deehw`.
- No private data in the repo (no home paths, real usernames or emails).

### Open work, in order

1. **Open the PR** for `phone-overnight-polish`, with this document as its summary.
2. **Panel round 3.** Re-render, re-record the walk-through, and re-run the four personas on the same brief. The target is 8+/10.
3. **Round 2 items still open.** None of these conflict with the user's decisions:
   - **The "needs you" line above the mic.**
     - Its dot is green, but green means *working* in Find; make it the asking yellow.
     - Give it an opaque band so terminal text never shows through it.
     - Keep the dot at a fixed offset from the text; it moves between frames.
     - Left-align it on the terminal gutter.
   - **Sheets.**
     - The Agent sheet covers about 75% of the screen for three rows; size sheets to their content.
     - The sheet titles "Project" and "Agent" sit about 4pt right of the rows below them.
     - Consider the system grabber.
   - **Placeholder contrast.** #8B8B8B on the #2C2C2C raised field is 4.1:1. Use about #9A9A9A (5:1).
   - **The Unlock page** says "Machines → studio → Set password". Check what the desktop menu actually calls it first, then use the same word, with ▸ as elsewhere.
   - **The sample.**
     - The pick-up heading should say it is a sample.
     - The placeholder in Claude's input line (`Try "run the…`) runs under the mic; shorten it in `lib/demo/sample_scripts.dart`.
     - "Try the sample" should be a first-class row near the top of the set-up page, not the last, dimmest line.
   - **Settings:** the lone "?" avatar is the only blue in the app.
4. **Dead code** found by the desktop-cut engineer, now with no callers:
   - In `app_state.dart`:
     - `SpokenTaskRequest`, `spokenTasks`, `reportVoiceRoute` and the handling of `voice_route_request`;
     - `selectAutonomousEnv`;
     - `hasNavigationRail`, and the pin and grid-keyboard methods (`togglePinPane`, `focusLastPane`, `toggleZoomPane`, `focusPaneBy*`, `movePaneBy`, `reorderPane`);
     - `paneFocusRequest`, `seedSwarm`, `openAgentFromDial`.
   - Elsewhere:
     - `DialState.restore`;
     - `WsTransportKind.localPlaintext` in `ws_conn.dart`/`ws_pool.dart`;
     - ApiClient's no-auth `localCliBaseUrl` mode;
     - `TerminalLinkOpener.open(isLocalMachine:)`;
     - the `cliLog` channel.
5. **Coverage gaps**, weakest first: `settings` (46%), `clipboard`, `logging` (73%), `terminal` (75%), `demo` (77%), `state` (80%).

### Proposals that need the user's decision (do not build without it)

- **Push notifications** that say what a harness wants, with Yes/No as notification actions. Priya and Sam both named this as the thing that makes the app daily.
- **A one-line Focus header** (`fix-login · studio:web`), pinned while reading history. The branch line would move to the title sheet.
- **Dynamic Type.** `lib/app_shell.dart` pins text scaling to the in-app "Text size", so iOS Larger Text is ignored. Jordan rated this a blocker.
- **Settings duplicates:** "Text size" beside the terminal's "Size", and "App colors" beside "Colors". All four personas asked for one of each. They mirror separate desktop settings, which is why they were kept.
- **Streaming the words into the `>` line while recording.** This is display only; auto-send is unchanged. First check whether the speech engine gives partial results.
- **The pick-up screen.** Two personas called it Find with a headline; they suggest launching into the last harness, or Find.
- **Unseen finished harnesses under "needs you"**, with their last line.
- **Discoverability:** a visible `⌄` on the Focus title, and a visible route to Find and New for Voice Control and Switch Control users.
- **Sentence case** ("New harness", "Open folder"). This touches desktop naming, which uses "New Harness".

### Outside this branch

- **Desktop PR #393** ("Your phones", with Remove, on the Mac) is waiting for the user to merge it.
- **Website `/pair` page:** PR autonomous-ai/autonomous-code#4 needs a `_web` tag to deploy.
- **TestFlight** is blocked until someone is on the release Mac, which has the App Store Connect key. Until then, the phone is a local `devicectl` install only.
