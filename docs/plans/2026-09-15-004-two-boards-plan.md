# One firmware for two dials: runtime board detection

Status: implemented · 2026-09-15

## Context

Two physical dials will ship at once. Same panel (CO5300 466×466 over QSPI), same audio (ES7210 @0x40 /
ES8311 @0x18), same I2C/I2S/QSPI pins, same UI, cable protocol and OTA. They differ only under
`board/`, `touch.c` and `ptt.c` (`~/Downloads/TOUCH_AND_BUTTON_PORT.md`, measured on two units):

| | Board A (what the repo targets today) | Board B (the port doc) |
|---|---|---|
| Touch controller | CST9217 @ `0x5A`, `mirror_x/y = 1` | CST816S @ `0x15`, no mirror |
| LCD reset / touch reset | GPIO39 / GPIO40 | GPIO1 / GPIO2 |
| PMIC AXP2101 @ `0x34` | present: battery %, charging, PWR key | **absent** |
| Screen sleep/wake key | PWR key via PMIC (`power_take_pwrkey_tap`) | BOOT held ≥ 800 ms |
| Touch driver component | `waveshare/esp_lcd_touch_cst9217` | `espressif/esp_lcd_touch_cst816s ^1.1.2` |

Today every one of those is a compile-time constant (`main/board/board_pins.h`) and there is one
binary, one OTA manifest, one `make upload-circle`. Two build targets would mean two manifests, a
dial that has to know its own SKU (eFuse/NVS at the factory), two release paths and the failure
"wrong image flashed → no touch". None of that is needed: **every difference is a fact the bus can
answer at boot**, so one image detects the board and configures itself. The daemon, `harness flash`,
OTA and CI stay exactly as they are.

Not per SKU — per **feature**: `has_pmic`, `touch chip`, `reset pins` are read independently, so a
future batch mixing them (CST816S + AXP2101, say) is right without a "board C".

## Detection (the whole design in one function)

`main/board/board.c` — `board_detect()`, run first thing in `app_main`, before `display_init()`:

1. `board_i2c_get()` (bus is common to both boards).
2. **PMIC**: `i2c_master_probe(bus, 0x34, 50)` — ACK ⇒ `has_pmic`. No reset involved; the AXP2101
   is always live on the bus. This is the most reliable fact, taken first.
3. **Reset both candidate pairs**: pulse GPIO39/40 then GPIO1/2 (low 10 ms, high, wait 50 ms —
   what both touch drivers do internally). Per `board_pins.h` GPIO1/2 are unused on A and
   GPIO39/40 unused on B, so the "other" pair is a no-connect on each board. ⚠️ This is the one
   assumption the code cannot verify itself — **step 0 below measures it on both units before anything
   is written**.
4. **Touch**: probe `0x5A` ⇒ CST9217 (mirror XY, rst 39/40); else probe `0x15` ⇒ CST816S (no
   mirror, rst 1/2); else `TOUCH_NONE` (UI still boots, as it does today when touch init fails).
5. Result: `const board_t *board(void)` — `{ lcd_rst, touch_rst, touch (enum), touch_mirror,
   has_pmic, name }`; one INFO line `board: touch=cst816s pmic=no rst=1/2 acks=15,18,40` that goes
   up the cable into `dial-*.log`.
6. Pure decision table `board_from_acks(const uint8_t *acks, int n, board_t *out)` — host-testable.

Fallback if step 0 shows the cross-pulse is NOT harmless: order the reset by the PMIC answer
(PMIC ⇒ pulse 39/40 and probe `0x5A`; none ⇒ pulse 1/2 and probe `0x15`), and only on a miss pulse
the other pair and probe again. Same result, one more branch.

## Changes

### Firmware `device/esp32-circle/main/`
- **`board/board.{c,h}`** (new): `board_detect()`, `board()`, `board_from_acks()`, the two pin
  tables. `board_pins.h` keeps only what is common (QSPI, I2C, I2S, BOOT, INT=11); `BSP_LCD_RST`,
  `BSP_TOUCH_RST`, `BSP_TOUCH_I2C_ADDR`, `BSP_AXP2101_I2C_ADDR` move into the tables.
- **`ui/display.c`** `panel_bringup()`: `.reset_gpio_num = board()->lcd_rst`.
- **`ui/touch.c`** `touch_open()`: both drivers compiled in; `switch (board()->touch)` picks
  `esp_lcd_touch_new_i2c_cst9217` or `..._cst816s`, io config macro per chip, `.rst_gpio_num =
  board()->touch_rst`, `.flags.mirror_* = board()->touch_mirror`. `touch_reinit()` unchanged (both
  drivers are `esp_lcd_touch_handle_t`). The `ESP_ERR_INVALID_RESPONSE` = "no finger" rule
  (2026-09-15) is a CST9217 fact — keep it under `if (board()->touch == TOUCH_CST9217)` and measure
  what CST816S returns idle (step 3) before deciding its branch. Log `CST816S: IC id` / `Chip Type`
  after init as the second confirmation.
- **`board/power.{c,h}`**: `power_init()` returns false without touching the bus when
  `!board()->has_pmic`; getters already answer -1/false when `s_dev == NULL`. Drop the doc's stub
  approach — one file serves both.
- **`ptt.c`**: BOOT long-press ≥ 800 ms toggles `display_sleep/wake` **on both boards** (one UX to
  teach, one code path; the doc's snippet). PWR-key tap stays on A (`if (board()->has_pmic)`),
  polled as today. Short BOOT tap = interrupt turn, unchanged.
- **`ui/ui_screens.c`**: nothing — the charge bolt already keys off `power_is_on_external()`; a
  Settings battery row, if any is added later, gates on `board()->has_pmic`.
- **`cable_client.c`** `send_hello()`: add `"hw": board()->name` (`"cst9217+axp2101"`,
  `"cst816s"`, …). Additive JSON, proto version unchanged.
- **`idf_component.yml`**: add `espressif/esp_lcd_touch_cst816s: "^1.1.2"`, keep the cst9217 one.
- **`sdkconfig.defaults`**: nothing expected; verify both drivers link without Kconfig.

### Daemon `cli/src/cable/`
- `cableSession.ts` hello: read `hw` (optional), include it in the `cable: dial … on fw … proto …`
  line and in `DialStatus` (`hw?: string`) → `dialStatus` push. `dialLog.greeted()` unchanged.
- `docs/specs/cable-protocol.md` §hello: document `hw` as optional, informational.
- Tests: `cableSession.spec.ts` — hello with/without `hw` both greet; the log line carries it.

### App `desktop/`
- `dial_status` already reaches the app; show `hw` beside fw where the dial's firmware is shown
  (Settings ▸ About / the flash dialog). Small, optional; skip if no such surface exists today.

### Host tests `device/esp32-circle/test/`
- `test_board.c` + a line in `run.sh`: `board_from_acks` table — `{34,5A,18,40}`→A,
  `{15,18,40}`→B, `{15,34,…}`→cst816s+pmic, `{}`→none. Also that `board.c` compiles on the host
  (isolate the decision from `driver/gpio.h` via a thin `board_detect.c`/`board_table.c` split).

### Docs
- `device/esp32-circle/README` (or `RELEASE.md`): "Two boards, one image" section with the table,
  the detect order, and the verification recipe from the port doc (I2C ACK list, `IC id: 183`).

## Order, and which dial to plug in

| step | what | plug in |
|---|---|---|
| 0 | **Measure before writing.** Throwaway probe in `app_main` (behind `#if 0`-style flag, never committed): scan 0x08–0x77, print ACKs; then pulse 39/40 *and* 1/2 and scan again. Confirms (a) the ACK table, (b) the cross-pulse is harmless, (c) CST816S's idle `read_data` return code. | **B first**, then A |
| 1 | `board.{c,h}` + host test + `board_pins.h` split. `make device-test`. | none |
| 2 | `display.c`, `touch.c`, `power.c`, `ptt.c`, `idf_component.yml` on the new tables. Build. Flash → boot log `board: …`, `CST9217 touch ready`, tap lands where the finger is, PWR tap sleeps, BOOT long-press sleeps. | **A** (regression) |
| 3 | Same image, no rebuild. Boot log `board: touch=cst816s pmic=no`, `CST816S: IC id: 183`, taps not mirrored, BOOT long-press sleeps/wakes, no `i2c transaction failed` spam, `alive` heartbeat every 60 s, `read-fails` absent in it. | **B** |
| 4 | `hello.hw` + daemon + spec + spec tests. `make install-cli`; dial log shows `on fw … hw cst816s`. | B, then A |
| 5 | Voice on both (mic path is shared — a sanity check, not expected to differ). Notification tap, swipe, question close. | both, one after the other |
| 6 | Publish: `make release-cli`, `make upload-circle` (one image) → both dials OTA to it; watch `boot: reset reason` + `board:` lines in each dial's log after the update. | both, cabled in turn |

## Verification
- `make device-test` green (new `test_board`).
- `idf.py build` clean; `cli`: `tsc`, `vitest run src/cable`.
- Board A: no behaviour change except BOOT long-press now also sleeps the screen.
- Board B: touch, sleep/wake, no PMIC noise in the log, OTA works from the same manifest.
- `~/.harness/logs/dial-*.log` for each board contains `board:` at boot and `hw` in the greeting.

## Out of scope
- Battery UI for B (there is no battery).
- A second OTA manifest or SKU eFuse — explicitly rejected above.
- Any UI/LVGL change.
