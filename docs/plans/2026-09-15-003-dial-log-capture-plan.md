# Dial log capture: make "the dial got stuck" traceable from a file the user can send

Status: implemented · 2026-09-15

## The problem

A recurring report: the dial **stops taking touch** — no swipe, the Voice button does nothing, the
screen sits on an agent tile — while the cable is plainly alive: switching panes in the app moves the
dial, notifications still ring, "task done" still beeps. So the reader task, the LVGL task and the
panel are all running; what died is the path from the glass to the gesture layer.

Nothing survives to be read afterwards. The dial keeps no log in flash. The daemon does receive the
firmware's log lines over the cable, but it writes them to **one unbounded file** that nobody looks
at and no tool exports:

| what exists today | where | problem |
|---|---|---|
| firmware `ESP_LOG*` lines, INFO level, framed as cable type `0x04` | `cable_link.c` `log_vprintf` | ships every line — but `touch.c` emits **five** lines in total (scroll totals and init failures); a gesture that never fires leaves no trace |
| daemon appends every log frame | `~/.harness/cli/data/dial.log` (`cableSession.ts:641`) | 3.7 MB since 2026-08-24, **never rotated, never pruned**, outside the app's log directory, not in Settings ▸ Debug |
| daemon's own log | `~/.harness/cli/data/harness.log` | has `cable:` open/close/silence/focus lines — the other half of the story, in a different file |
| app logs, per day, 14-day retention | `~/.harness/logs/app-*.log`, `cli-*.log` (`lib/logging/log_file.dart`) | the dial is not a source; there is no "export" — the user has to be walked through Finder |
| firmware reset | — | `esp_reset_reason()` is never logged; no task watchdog on the LVGL task; no last-words buffer — a panic + reboot looks like an unplug |

Bringing the device back to the desk does not help either: whatever happened is gone the moment the
cable is pulled.

## Goal

When it happens again, the person sends **one zip** and the log inside answers, in this order:
was the LVGL task alive · was touch data arriving from the controller · which gesture-layer flag was
holding the press · what was covering the face · did the device reset. Retention **7 days** for the
dial's log, bounded on disk.

## Plan

### 1. Daemon — the dial's log becomes a real log (small, ships first)

`cli/src/cable/cableSession.ts`

- Write log frames to **`~/.harness/logs/dial-YYYYMMDD.log`** — the directory the app already reads
  and prunes — one file per day, rolled at the first line after midnight. Stop writing `cli/data/dial.log`
  (leave a one-line pointer file for anyone with a bookmark).
- **7-day retention**: prune `dial-*.log` older than 7 days on roll-over (the app's `LogFile` does 14
  for its own; the dial's is chattier and the owner asked for 7).
- **Size cap** per day (20 MB): past it, write one `[daemon] dial log capped for today` line and drop
  the rest — a firmware stuck in a log loop must not fill the disk.
- Write the daemon's cable events into the **same file**, prefixed `[daemon]`: port open/close, hello
  (mac, fw, proto), silence-reopen, "not ours" release, focus pushes, agents/ring pushes, turn.started /
  turn.done / question relays, fw.offer. Today these are only in `harness.log`; a stuck report is read
  end to end from one file when both halves are in it.
- Line format stays `ISO-time <text>`; firmware lines keep their `I (ticks) tag:` prefix so the device's
  own clock (ms since boot) is beside wall time — a reboot shows as ticks going back to zero.

### 2. Firmware — say what the gesture layer is doing (the substance)

`device/esp32-circle/main/ui/touch.c`, `ui_screens.c`, `audio_client.c`, `display.c`, `app_main.c`

Throttled INFO lines, each written so a stuck case has a signature:

- **Touch samples.** One line per press (`press (x,y)`) and per release (`release (x,y) held=Nms`), and
  the verdict swipe_track reached (`tap` / `swipe ±` / `home` / `pull-down` / `scroll`). Never per
  sample — a drag is one `scroll:` line, as today.
- **The controller.** `esp_lcd_touch_read_data` returns an `esp_err_t` that `touch_read` ignores. Log the
  first failure and every 100th after it (`cst9217 read failed: 0x%x (n=…)`), and keep a consecutive-
  failure counter: past 50 (~1 s) log `cst9217 dead — reinit` and re-run the init path. This is also
  the first real *fix* candidate, not just a log.
- **The flags that swallow input.** `s_swallow_until_release`, `s_goal_swallow`, `action_capture`, the
  notification band's `ncap`, and `ui_voice_is_active()`: log when each is **set** (with why) and when it
  **clears**. A **stuck watchdog** in `touch_read`: any of them held > 5 s with no release sample →
  `WARN touch: <flag> held 5s, last sample pressed=%d (x,y)` once, then every 30 s. If the report matches
  the symptom, this line names the flag.
- **What covers the face.** `ui_screens.c`: one line on every screen load and on every top-layer overlay
  shown/hidden (voice overlay, dim, notification drawer, agent switcher, picker, lock). A press eaten by
  an invisible clickable overlay is otherwise indistinguishable from dead touch.
- **Voice.** `audio_client_active` transitions with the reason (`begin`/`end`/`abort`/`quota`), and a
  WARN if it stays active > 10 min — touch.c forwards nothing to LVGL while it is, which is exactly the
  reported shape (swipe dead, Voice dead, screen still following the app).
- **`display_lock` contention.** Any wait > 2 s logs the waiting task and the caller (a macro that passes
  `__func__`), so a deadlock between the reader task and the LVGL task is visible as the last line before
  silence.
- **Liveness heartbeat.** Every 60 s from the LVGL task: `alive up=%us heap=%u/%u lv=%u touches=%d
  last_press=%us`. Cable lines continuing while this one stops = the LVGL task is wedged. Its absence is
  the evidence, so the daemon marks the gap: `[daemon] no dial heartbeat for 90s` in the same file.
- **Reset reason and last words.** On boot, log `esp_reset_reason()` right after `hello`. Keep a 4 KB
  ring of the most recent log lines in `RTC_NOINIT_ATTR` memory (survives a soft reset, not a power
  cut); when the reset reason is panic / task WDT / interrupt WDT / brownout, replay the ring after the
  reset line as `last:` lines. Enable the **task watchdog on the LVGL task** (`CONFIG_ESP_TASK_WDT`,
  `esp_task_wdt_add` in the LVGL loop, `esp_task_wdt_reset` per tick) with panic → reboot, so a wedged
  UI task becomes a reboot with a stack in the log instead of a frozen glass.
- **Log level stays INFO**; the new lines are gated by rate, not by level, so a shipped build carries
  them. Budget: under ~40 lines/min in normal use (the heartbeat is one; a busy minute of swiping is a
  few dozen).

### 3. App — Settings ▸ Debug reads it and one button exports it

`desktop/lib/logging/`, `desktop/lib/settings/sections/debug_*.dart`

- A **Dial** source beside App and CLI in Settings ▸ Debug: a mirror of `dial-*.log` through the same
  `installFileLogs` ring, filterable by tag (`touch`, `ui`, `cable_client`, `[daemon]`).
- **Export logs** (toolbar button, also `harness logs export` in the CLI for a desk with no window): zip
  the last **7 days** of `app-*.log`, `cli-*.log`, `dial-*.log`, the tail of `harness.log` (last 5 MB),
  `harness status --json`, the app version and the dial's last hello (fw, mac) into
  `~/Desktop/harness-logs-YYYYMMDD-HHMM.zip`, every line through `redactSecretsInText` first. This is
  the file the owner asks for.
- The Debug pane's paths card lists the dial log beside the others.

### 4. What we expect to learn (the hypotheses the new lines separate)

| if the log shows… | it was… |
|---|---|
| heartbeat stops, cable lines continue | LVGL task wedged (display_lock deadlock line just before, or nothing = hard hang → the task WDT now reboots it with a stack) |
| `cst9217 read failed` runs, presses stop | touch controller / I2C hung → the reinit path either recovers it or names the fault |
| `touch: swallow_until_release held` / `goal_swallow held` | a release the controller never reported left the gesture layer holding the press |
| `audio_client_active` never ended | a voice upload with no terminal frame keeps every touch away from LVGL |
| overlay shown, never hidden | an invisible clickable layer (dim, drawer, picker) eating presses |
| `reset: panic` + `last:` lines | a crash that the daemon's silence-reopen made look like an unplug |

### 5. Order and size

1. Daemon rotation + `[daemon]` markers + 7-day prune — ~half a day, no firmware flash, immediately
   turns the next report into a file.
2. Firmware instrumentation + controller reinit + heartbeat + reset/last-words + task WDT — one to two
   days; the reinit and the WDT are the parts that may *fix* the symptom rather than describe it. Ships
   by `make upload-circle`, so it reaches every dial within ~6 h of publishing.
3. App Dial source + Export — one day.

Nothing here touches the wire protocol (log frames already exist), the ring, or the swarm plumbing.
