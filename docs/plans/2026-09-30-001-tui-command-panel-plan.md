# hn: one command panel, the desktop's features in it, a vertical status bar

Status: **IN PROGRESS** — worktree `autonomous-harness-models-ux`, nothing committed yet.

## Goal

A terminal user of `hn` remembers **one key** (`prefix + Enter`), types what they want
(`theme`, `models`, `link`, `new`…), and drives everything with **arrows + Enter**. Every list
opens in **one panel component** that looks the same everywhere, follows the chosen theme, and
never moves. The TUI reaches parity with the desktop app's features, drawn the TUI way.

**Focus (owner, final): theme → config → machine → local model.** Merge in that order (agent A,
then B, then C); `hn-dev` is updated after each merge for the owner to try.

## Status at 18:33 (overrides the Status column below where they differ)

All three agents' work is merged into this worktree; the full suite passes (243/243, no build
warnings); `hn-dev` (18:32) carries it. Nothing committed.

| Rows | State | How it was checked |
|---|---|---|
| Q1–Q10, Q14–Q15, Q17–Q19, Q21, Q30–Q31, Q34, Q39, B1–B5 | Done | tests; live in an isolated hn |
| Q11, Q28 (local models; switch the current pane's model) | Done — agent C, merged | its 17 tests with fake daemon replies; live shows the offline notes only (no daemon in the isolated run) |
| Q12, Q22, Q29 (Connect machine, Add phone + QR, machines & devices; robots dropped) | Done — agent B, merged | its 14 tests incl. QR encode → draw → decode round trip; live offline states |
| Q13, Q16, Q20, Q36, Q42 (side bar: current machine → windows → nested panes with name + repo; no tab row) | Done | tests; live |
| Q23 (box panes, focus/attention colours) | Done | tests; live |
| Q48 | No round marks anywhere (● ○ ◌): the harnesses' own marks | Done — state marks (spinner for starting, `·` offline), `theme::machine_mark` (`✓`, spinner, `?`, `✗`, `·`), `✓` for a chosen value / an installed package / a model in use |
| Q49 | Launcher bottom block as fzf had it: keys line, `n/m (marked)` + rule, the query with the scopes | Done |
| Q50 | Bigger panel (nine tenths of the window) | Done |
| Q51 | Harnesses list: no state headings, most recent first | Done |
| Q52 | No scrollbars | Done — panel list and preview |
| Q53 | Models: hide a Shared grid with nothing to show ("Nobody was serving here…") | Done — kept while waking or when it can be woken |
| Q54 | Engine icons for the subscription quota in the side bar footer (`✳ 43%`), not in window/pane names | Done — `#{usage_remaining_icons}` |
| Q55 | Commands' "App" group and "Quit" unclear | Done — group "Settings & help": Appearance…, Keyboard shortcuts…, Quick help, Close hn |
| Q56 | Side bar: no `grouped`/`flat` switch, no ` new` / `menu` row | Done |
| Q57 | Idle windows/panes showed a meaningless `·` | Done — no mark when idle, paused, offline or a shell |
| Q58 | Clicking or focusing a pane another window has the keyboard of should take it, not wait for typing | Done — `App::take_if_watching` on focus and window switch; test |
| Q46 | Space around panes: exactly one cell everywhere — at the window's edges as between two boxes, across and down — never doubled, as the desktop app spaces its panes | Done — `App::box_inner` (a cell off each edge without a gap of its own; the side bar's blank edge counts) + `pane_frame::boxed_in`; test `the_space_around_every_box_is_one_cell_across_and_down` (5 layouts); live, bottom status and left bar |
| Q47 | Side bar footer: no time, no "left" | Done |
| Q43 | Launcher's scope strip (`harnesses > commands @ machines…`) at the bottom of the panel | Done — live |
| Q44 | Appearance: drop "Border line" and "Indicators" (tmux.conf keeps them); "Border style" becomes **Borders on/off** | Done — tests |
| Q45 | Side bar footer was a jumble (status-right cut into lines: long session name, one count a line, machine again) | Done — structured: daemon (when down), `Claude 43% left`, counts on one line, time; nothing already shown elsewhere |
| Q33 | **Reverted at the owner's word** (18:40): the shared line made panes look glued, the titles running into each other. Each pane is its own box again, a cell apart, as the reference shows | tests `boxes_frame_each_pane_a_cell_apart…`, `each_pane_is_its_own_box…`; live |
| Q35 (rename window / session) | Done | live, status bar at the bottom and with the side bar |
| Q40 (usage & status line in the side bar's footer, session name first) | Done | tests; live (usage needs a daemon) |
| Q41 (drag the side bar's width, kept in tui.toml) | Done | tests |
| Q37 (accent from the terminal's own palette via OSC 4) | Done in code | tests of the picking; not seen live yet — needs the owner's Ghostty |
| Q38 (New Harness in the panel, chooser in place) | Done | test `the_form_stays_put_when_a_chooser_opens` |
| Commands: tmux commands hidden until you search; hints only in Commands/Appearance; bigger preview | Done | tests; live |
| ↑N/↓N ahead/behind on a pane's repo line | Not possible yet | the fleet data has no ahead/behind field |
| Q8 / step 3 (install as plain `hn`, restart the hn server) | Waiting for the owner's go | — |

## Rules for every step (from the owner's requests)

| # | Rule | Where it is enforced |
|---|------|----------------------|
| R1 | One panel component for every list/modal: centred, dimmed backdrop, **no border** | `tui/src/settings.rs` (`chrome`, `fill`, `backdrop`, `area`) |
| R2 | Fixed position and size — stepping into a section or filtering never moves it | `settings::area` depends on the window only; test `the_panel_does_not_move_when_a_section_opens` |
| R3 | Panel colours follow the current theme (native when none is chosen) | `settings::chrome` from `theme::pane_palette()` — **step 4** |
| R4 | Only arrows + Enter (+ Esc/← back); typing filters | `input.rs` picker keys, `settings::top_down` |
| R5 | A preview shows the whole result and does not jump; hovering changes only its own part | `settings::preview`, `Look::with` |
| R6 | Works as plain `hn` — never a path to a dev binary | install step (see "Shipping") |
| R7 | Verified in the real binary, isolated from the live daemon, before reporting | "How each step is verified" |
| R8 | Ask before every commit and push | — |
| R9 | Never change what a tmux key does; hn's keys go only where tmux has none | `keys.rs` test `every_tmux_key_does_what_tmux_does` |
| R10 | The product never names the outside projects used as design references | grep before every commit |

## Requests, one line each, with status

| # | Request (owner's words, condensed) | Status |
|---|---|---|
| Q1 | Inside a section no options showed | **Done** — refresh no longer rebuilds the settings list (`input.rs` `refill`) |
| Q2 | Remove the border, like the new-harness modal; one ratatui component | **Done** — panel has none; New Harness form lost its border and shares `settings::chrome` |
| Q3 | Modal must not move when entering a section (as prefix+N does) | **Done** — settings/commands/all lists; the New Harness form is placed as if its chooser were open, so opening one never moves it (test `the_form_stays_put_when_a_chooser_opens`) |
| Q4 | Preview shows all sections at once and doesn't refresh away | **Done** — mini hn: panes, borders, title rows, indicators, focus, layout, theme, status bar |
| Q5 | Preview status bar follows the theme | **Done** — preview palette built from the theme (`theme::pane_palette_of`) |
| Q6 | Choosing a theme really recolours hn (not only the accent) | **Done, to verify live** — theme colours stand in for the terminal's (`term_out::set_theme_colours`), pushed to daemons (`push_theme`); "Terminal default" row resets |
| Q7 | Opencode-style palette: one key, type `theme`… | **Done, to verify live** — `prefix + Enter` → Commands panel; Settings opens in place, Esc returns. (Space stays tmux's `next-layout`: no tmux key changes — owner's rule R9.) |
| Q8 | Open it from `hn`, not a path | **Step 3** — install the build as `hn` |
| Q9 | Modal style native / synced with the current theme | **Done** — `settings::chrome_for(pane_palette)`; verified live (panel 38,39,40 → 44,44,47 on a theme change); New Harness uses the same |
| B1 | Bug: typing in a section (e.g. `adwaita` in Theme) left the cursor on the 2nd match | **Done** — panel lists go to the best match on every query change; test |
| B2 | Commands rows show no key for hn's own entries (`New Harness…` should say `C-b N`) | **Done** — `modal::own_key` maps each entry to the command its key runs; test |
| B3 | Tests wrote the real `~/.config/harness/tui.toml` (a new test did, once — restored byte-for-byte) and could write `~/.harness/tui/*` | **Done** — under `cfg(test)` `config::path()` and `app::state_dir()` are a per-process temp folder |
| Q10 | prefix + s (search) in this modal | **Step 5** |
| Q11 | Local models in this modal, with desktop parity | **Step 6** |
| Q12 | Link device section | **Step 7** |
| Q13 | Status bar vertical (left/right) or horizontal; tabs shown; grouped by linked machines; single-pane group | **Step 8** |
| Q14 | Other desktop features brought into the TUI in this modal | **Step 9** — inventory below |
| Q15 | Rename "Status line" section (it is pane title rows) to avoid clashing with the status bar | **Done** — now "Pane titles" |
| Q16 | Vertical bar in the owner's reference style: machines → windows → panes grouped, click to navigate, tmux keys still work | **Step 8** |
| Q17 | Make sure nothing is missed; a detailed plan | This file — every request gets a row here |
| Q18 | Every current list in this panel: prefix + s "Search harnesses", `>` commands, `@` machines, `#` projects, `:` models, `*` store, `?` help | **Done** — every picker is a panel (`@hn-lists fzf` brings fzf's look back); the launcher shows its scope strip; verified live |
| Q20 | Vertical bar: machines, each with its windows grouped; top part = the current window's panes, the selected one highlighted | **Step 8** |
| Q21 | Group rows in the panel under titles, like opencode | **Step 5a** — group headings in `settings::list` (Row.group, never drawn until now) |
| Q22 | Connect machine (as the app has it) and Add phone, the QR code shown like the app's | **Step 7** — same QR payload/link as `add_phone_dialog.dart`, drawn with half-block cells, scannable at the panel's size |
| Q23 | Panes drawn as boxes by default (each pane its own single-line frame, as in the owner's reference); the frame changes colour when the pane is focused or its harness needs permission/input — as the app shows its coloured line | **Step 8** (agent A) |
| Q25 | Owner: the swarm/team conversation view and the notifications work (inbox + settings) are **not needed** | **Dropped** |
| Q27 | Owner: scope is **config + connect machine (core) + local models** only; the rest of step 9 (share, filters/sort, account, usage, about, store) not needed now | **Dropped** — agents D1/D2 stopped, their worktrees and code deleted; nothing of theirs was merged |
| Q29 | Owner: Connect machine and **Add phone** are in the core scope | **Step 7, first priority** (agent B); Robots & dial **dropped** (owner, final) |
| Q30 | Launcher fixes from the owner's screenshot: `@` lands on this machine with its preview; fewer footer keys (Enter, Esc, and "answer" only when the row waits on you); rows ran off the panel (a long right column: project + machine + age) — also seen after `@` then ⌫; blue text | **Done** — right column uses its short form and ≤ ⅓ of the row; headings muted bold, cursor row in text colour bold; regression test `long_rows_stay_in_the_panel_and_at_lands_on_this_machine` |
| Q31 | Pane borders: a full box around each pane, not a shared line in the middle | **Done** — agent A merged; verified live (separate frames, 1-cell gap, focused frame in the accent, others muted) |
| Q32 | Tabs over the panes with the side bar didn't follow the theme | **Superseded by Q36** (the tab row is removed) |
| Q33 | Less space between panes: box frames share one line between neighbours (`┬ ┴ ├ ┤ ┼`), no double border + gap | **Next** (main agent, after agent A's bar rework lands) |
| Q34 | "Settings" is really **Appearance** | **Done** — panel title, Commands entry "Appearance…", `:appearance`, placeholder |
| Q35 | Test rename session / rename window (prompts) with the new chrome | **Next** — live, with the status bar at the bottom and the side bar |
| Q36 | Side bar: no tab row; its top part groups **windows → panes** like the machines part; each pane shows name + repo (project · branch) as before | **In progress** (agent A, in the main worktree) |
| Q37 | Active pane border, current tab and tab text were a fixed teal, not the terminal's theme | **Done in code** — with no theme chosen the accent comes from the terminal's own palette (OSC 4, colours 1-7, picked as a bundled theme's is); fixed teal only if the terminal doesn't answer |
| Q38 | New Harness form sat off-centre; it should look like the menus | **Done in code** — the form is the panel (`settings::area`), a chooser opens in its place |
| Q39 | Pane titles default **top** (off / bottom are the user's choice) | **Done** — default back to top |
| B4 | Commands search: `appe` ranked tmux's set-buffer over Appearance (matched its description) | **Done** — Commands match names and keywords only (`picker.live`) |
| B5 | Tests raced on the global colours (theme/accent) | **Done** — `term_out::colours_lock()` in every test that sets or compares them |
| Q40 | With the side bar the subscription usage metric (status-right) disappeared; show it at the bottom | **In progress** (agent A) — footer block of the bar: usage remaining, fleet counts, daemon, watching, where, clock (status-right's own formats) |
| Q42 | Side bar top: the header is the **current machine's name** (not "panes"); under it the windows, each with its panes nested | **In progress** (agent A) |
| Q41 | The side bar can't be dragged narrower/wider | **In progress** (agent A) — drag the separator (18–36), double-click resets, width kept in tui.toml |
| Q28 | Switch the model of the **current pane** like the app: subscription runs out → open the picker → switch to a local model (download → start → serve → retarget), and back | **Step 6, first priority** (agent C told) |
| Q26 | Home screen (wordmark) follows the theme | **Done** — wordmark already used the theme accent and text the theme's colours; with a theme chosen the screen now stands on the theme's background (`themed_home`); test |
| Q24 | Work split across parallel agents | Agents A (step 8 + Q23), B (step 7 + Q22), C (step 6), D (step 9); step 5 + merge + install in the main worktree |
| Q19 | Keep the preview (in every list that has one) | **Done** — `ui::panel_preview` runs the list's own preview on the right (the live harness screen included); verified live |

## Steps

### 1. Settings panel — done
`hn theme` / `:theme`: sections (Pane titles, Indicators, Border line, Focus, Split direction,
Layout, Theme) → options; Enter applies live and writes `~/.config/harness/tui.toml` `[look]`
(folder created if missing). Theme list starts with **Terminal default**.

### 2. Commands panel — done, to verify live
`prefix + Enter` (unbound in tmux; command `choose-command`). Rows: hn's commands by menu name,
then every tmux command, each with its real key. Enter runs; commands needing words open the `:`
prompt prefilled. **Settings…** turns the same panel into Settings; Esc/← comes back to Commands.

### 3. Ship it as `hn` (Q8)
`hn` → `~/.local/bin/harness tui` → `~/.harness/bin/harness-tui`. Install the release build there
the way earlier dev builds were (keep a `harness-tui.bak.<stamp>`; copy then `mv`, never overwrite
the running file in place). The running `--local-server` keeps the old binary until it restarts —
**ask the owner before restarting it** (it serves their live harnesses). Check `hn --version`
and that the automatic updater will not immediately put the release build back.

### 4. Panel colours follow the theme (Q9, R3)
`settings::chrome()` today uses fixed greys (25/25/25, 247/247/247). Derive from
`theme::pane_palette()` (which now follows `@hn-theme`): panel = `surface` lifted toward
`foreground` a few %, muted = `pal.muted`, selected row = `inactive_surface`, accent =
`theme::accent()`, backdrop = `canvas` dimmed. New Harness uses the same `chrome`, so it follows too.
Test: two themes → two different panel surfaces; NO_COLOR still readable.

### 5. Search (prefix + s) and the other lists in the panel (Q10, Q3, Q18, Q19)
The launcher's header shows its scopes as today (`Search harnesses · > commands · @ machines ·
# projects · : models · * store · ? help`); typing a scope character switches the list **inside
the same panel** (same place, same size) and the right side shows that list's preview.
`choose-tree -s` / the launcher (`PickerKind::Open` and its `@ # > : * ?` scopes) drawn by
`settings::draw` instead of fzf full-screen: list left, the **live pane preview** right (reuse
`ui::preview` into the panel's right rect). Keep fzf semantics: scopes, marks (Tab), C-v/C-x/M-…
keys, the "said" search, live re-ranking. Mouse: rows, wheel, preview scroll. Then Machines,
Projects, Store, Layout, Help, Keys, Buffers → one list at a time, each with a test.
Also: the New Harness side chooser keeps the form where it is (no re-centre).
Keep an escape hatch: users with `FZF_DEFAULT_OPTS` set keep fzf's look? — **open question O1**.

### 6. Local models in the panel (Q11) — desktop parity
From the models survey (desktop file:line in the survey notes):
- Rows by section: **This computer** (memory/disk line), **Shared · <grid>**, **Subscriptions**,
  **APIs**; each row: name, size, tok/s (measured or `~` estimate), state word
  (Get / Downloading n% / Running / ● In use).
- Preview: size, download + free disk, memory fits/needs, speed, **context window**, params, quant,
  machine, state, the Enter sentence.
- Actions: Enter = **Use** (download → start → wait → `agent_retarget {agentId, gridModel, gridName}`),
  `^S` stop; one local model runs at a time; progress from `operation`.
- Polling: every 4 s while busy/visible, else 60 s; `grid_models_changed` push.
- Per-pane model switch (`agent_retarget`, `clearGrid`) and the pane's "Starting up…" note.
- Resting shared sections: "Show models" wakes (`grid_models_list {wake}`), re-read 5 s up to 60 s.
- Backend: `grid_fleet_models_list`, `grid_fleet_model_{download,start,stop}`, `grid_models_list`,
  `agent_retarget`, `api_connections`.

### 7. Link device (Q12) — a **Machines & devices** view in the panel
Today the TUI can only link *to* a machine (M-l → password prompt → `harness link connect`).
Everything else is missing. Each row below is a Commands entry and a section in the panel:
- **This computer**: remote password status / set / change / clear —
  `harness remote-password {status --json | set --stdin --json | clear --json}`.
- **Linked from here**: list, refresh, unlink — `harness link list`, `harness link unlink <id>`.
- **Link a machine**: password prompt with the CLI's progress stages (connecting → deriving key →
  exchanging → verifying) from `harness link connect <id> --stdin --json` NDJSON.
- **Your machines**: online/offline, rename (`PATCH /api/machines/:id {name}`), remove from account
  (`DELETE /api/machines/:id`), and **Add a machine** (copyable install / login / password steps).
- **Add phone**: one-time sign-in code (`POST /api/auth/handoff`) + QR drawn with half-blocks;
  pairing via `phone_pair {code}`.
- ~~**Robots / dial**~~ — dropped by the owner (Q29): `harness autonomous-device {status|list|discover|pair --code-stdin --device|revoke}
  --json`; dial settings via `dial_settings`.
Writes (set password, unlink, remove, pair) ask y/n in the panel first.

### 8. Status bar: vertical or horizontal (Q13, Q15, Q16)
Reference: the owner's screenshot at the start of this task. What it draws, and what hn takes:

```
spaces                  │ ▆▆▆▆  +                          ← tab strip: active tab a filled accent block, + new
○ autonomous-grid       │ ┌───────────────┐┌───────────────┐
  main                  │ │ pane          ││ pane (active: │ ← thin single borders, active in accent
· ishot                 │ │               ││ accent border)│
○ autonomous-harness    │ │               ││               │
  feat/grid-harnes… ↑1  │
▌autonomous-harness     │   ← current row: filled highlight
new             ● menu  │   ← divider: new (harness) · menu (the Commands panel)
agents         grouped  │   ← toggle: grouped / flat
○ autonomou… · Omarchy  │   ← name · machine, dim
  claude                │   ← engine, dim second line
                     «  │   ← collapse the bar
```

hn's version (setting **Status bar**: `bottom` · `top` · `left` · `right`; `left`/`right` = the bar):
- Owner's words (Q20): "vertical will show machine, and group all the windows in that machine, and
  the vertical on top will show the single pane selected in that window."
- **Top section — this window's panes**: one row per pane of the current window (`1 claude`,
  `2 codex`…, engine + state dim), the focused pane highlighted. Click = focus that pane.
- **Machines section — machine → its windows**: each linked machine (● online / ○ away) as a
  heading, its windows (swarms) grouped under it; a window with panes on several machines appears
  under each of them. The current window highlighted. Click = select that window.
- **Divider**: `new` (New Harness) · `● menu` (Commands panel, = prefix + Enter).
- **Bottom section — harnesses**, `grouped` by machine (toggle `grouped` / flat by attention):
  name · machine (dim), engine + state (dim) on the second line; needs-you first.
- **Click** any row: machine → its first window; window → select it; pane → focus it; harness →
  open it (as the launcher does). Wheel scrolls the bar. `«` collapses it to a 2-column strip.
- **tmux keys keep working**: prefix n/p/0-9/w/s/o/arrows move the highlight with the real focus.
- Tab strip at the top (option **Tabs**: on/off), active tab filled with the accent, `+` = new window.
- Width 24 columns (O2). The body shrinks by the bar: `App::body`, `window_area`, mouse
  hit-testing, `status_ranges`, pane sizes (`fit_panes`), and the panel's `area` all follow.
- The preview in Settings draws the bar. "Status line" section renamed **Pane titles** — done.

Drawing rules to match (from studying the reference's source):
1. Bar 26 columns (clamp 18–36); its last column is a `│` separator in a dim surface colour that is
   also the resize handle (drag; double-click resets). Content uses width − 1.
2. Two sections split 50/50 (draggable 10–90 %, each ≥ 3 rows): top list, then a full-width `─`
   rule (the drag divider), then the bottom list.
3. Section header row: ` title` bold in the muted colour, a blank row after it; the bottom header
   has a clickable right-aligned mode label (`grouped` / `priority`).
4. Entries are 2 lines: line 1 at x+1 `ICON NAME`, line 2 at x+3 secondary text; 2 columns kept
   free on the right for a `▸`/`▾` group toggle. Children of a group use `├─ ` / `└─ ` prefixes.
5. Glyphs: `●` working/blocked/done, `○` idle, `·` unknown; colours yellow / red / teal / green /
   muted. Separator between parts ` · ` in the muted colour.
6. Name: text + bold when focused, else a softer text; second line accent-ish when focused, else
   muted. `↑N` green, `↓N` red, hidden when 0.
7. Highlight fills the whole 2-line entry: focused → active-row background; keyboard cursor →
   selection background.
8. Truncate by display width with `…`; share width between parts, dropping the leftmost first.
9. Footer row of the top section: ` new` left, `menu` right (a `●` accent before it when there is
   a notice). `«` at the bottom right collapses the bar to a 4-column rail (`n` + glyph per row,
   `»` to expand).
10. Tabs: one row; each tab label + 4 wide (min 8), centred label, 1-column gaps; active = filled
   accent with the panel colour as text; inactive = surface background, muted text; ` + ` after.
11. Pane borders: merged junction glyphs; accent where a cell touches the focused pane, muted
   elsewhere; title ` label ` in the top border, accent + bold when focused.
12. Mouse: press + release without moving = focus (window / tab); moving ≥ 1 cell = reorder drag;
   a harness row focuses its pane anywhere; wheel scrolls lists by one entry and switches tabs over
   the tab row; right-click opens a context menu (rename / close / new).
13. The bar keeps no focus of its own: it follows the real focus and scrolls the focused entry
   into view when focus changes.
14. Colours come from one palette (accent, panel, active row, selection, surfaces, muted, text,
   green/yellow/red/teal); the terminal-default theme uses ANSI colours + the terminal's background.

### 8a. Saved keys hide new default keys (found while testing step 2)
The hn server saves its **whole** key table in `~/.harness/tui/sessions-<name>.server.json` and
`server::take` → `keys_from` replaces the defaults with it. So an existing user never gets a key hn
adds later. **Done**: `Keymap::migrate_defaults` adds hn's new keys (today: Enter →
`choose-command`) where the saved table has nothing on that key; a key the user bound is left alone.
Also: tests read the real `$HOME` state file (pre-existing) — point tests at a temp `HOME`.

### 9. Other desktop features (Q14) — **DROPPED for now by the owner (Q25, Q27)**; kept as a list for later
From the desktop survey, in order of what a terminal user misses most:
1. **Share a harness**: invite by email for N days, list/remove people, public/private link —
   `harness_share_{list,invite,remove,link}`; **Shared with you** list.
2. **Notification inbox**: finished / failed / needs-input with read state (`agent_seen`,
   `app_unread`), not only questions; **Notifications** settings rows (on-screen, sound, OS) instead
   of the `HARNESS_TUI_NOTIFY` env var.
3. **Harnesses filtered and sorted**: needs input / running / paused filters; sort by recent / name /
   machine / project (the desktop's Harnesses panel).
4. **Account**: `harness auth status --json`, login, logout.
5. **Usage**: beyond quota — harnesses started, time, turns, tokens by model/project.
6. **About**: version, update check status.
7. **Store**: remove, ratings/reviews.
8. **Swarm conversation** (`team` RPC), **Experimental** flags (`/api/experimental-settings`).
Not for a terminal: wallpaper/background, UI font, flash firmware.

## How each step is verified (R7)

1. Unit tests for rows/keys/geometry; one test through `ui::draw` on a `TestBackend`.
2. Full suite once: `cargo test --release --color=never > scratchpad/tui-tests.txt`.
3. `cargo build --release`, then the real binary in a private tmux socket
   (`tmux -L claude-settings`), env `-u TMUX`, `PORT=19999` (no daemon — shows "daemon down"),
   `HOME`/`XDG_CONFIG_HOME` = scratch dir, `HN_SOCKET_NAME=claudetest`, `HARNESS_TUI_DESK=off`.
   Drive with `send-keys`, read with `capture-pane`; kill only the `claudetest` server after.
4. Steps that need the daemon (models, link device): read-only calls first; anything that writes
   (download, start, retarget, link) only with the owner's go-ahead.

## Open questions

- **O1** Should the launcher (prefix + s) always use the panel, or keep fzf's full-screen look
  when the user has `FZF_DEFAULT_OPTS` set?
- **O2** Vertical bar width: fixed (24 cols like the app) or a setting?
- **O3** ~~Replacing `C-b Space`~~ — decided: never change a tmux key; the panel is `C-b Enter`.
- **O4** A chosen theme recolours panes via the daemon's `theme_set` — the desktop app uses the same
  call, so the last one to set it wins on a shared machine. OK?

## Survey notes

Desktop model features vs TUI: 20 features, TUI has 2 fully (New Harness model choice, usage),
partial: local model list/start/download/stop, Store packages; missing: pane model switch, Models
panel, Model Manager, shared sections, wake, live push, onboarding, "New" badge, details preview.
