# Interns Commander Device (ESP32-S3-Touch-AMOLED-1.75C)

Firmware for a hardware companion that pairs to your Interns account and shows your Claude turns on
its 466×466 AMOLED screen — and lets you act on them. It is **interactive**: besides rendering the
live event feed per project, you can **speak a new instruction** (hold-to-talk), **answer the agent's
questions**, **interrupt a running turn**, and **create a project** — all from the device.

The device holds one WebSocket to the backend's `/api/commander-ws` hub endpoint (agent-scoped;
the backend still accepts the legacy `/proxy/api/commander-ws` alias for pre-canonical firmware)
and talks to a few REST endpoints for pairing and project discovery. OTA firmware is pulled directly
from a public GCS bucket (no backend involved).

## Hardware

- **Board:** Waveshare [ESP32-S3-Touch-AMOLED-1.75C](https://docs.waveshare.com/ESP32-S3-Touch-AMOLED-1.75C)
- **MCU:** ESP32-S3R8 (dual LX7 @240MHz, 8MB octal PSRAM, 16MB flash), 2.4GHz WiFi
- **Display:** 1.75″ AMOLED 466×466, **CO5300** driver over QSPI (LVGL v9)
- **Touch:** CST9217 (I2C) — used for swipe, tap-to-read, and double-tap sleep/wake
- **Audio:** ES7210 ADC (dual mic capture) + ES8311 codec (notification beep), shared I2S/I2C
- **PMIC / battery:** AXP2101 (I2C) — battery %, charging state, and the PWR key (button A)

## Prerequisites

- **ESP-IDF ≥ 5.5** ([setup guide](https://docs.waveshare.com/ESP32-S3-Touch-AMOLCD-1.75C/Development-Environment-Setup-ESPIDF))
- A WiFi network with internet — the device talks to the **production backend over TLS**
  (`wss://ac-api.autonomous.ai`); no LAN server is needed.

> ⚠️ **Verify the pin map.** `main/board/board_pins.h` follows Waveshare's reference design but the
> exact GPIOs come from their ESP-IDF demo (`02_lvgl_demo_v9`). If the panel stays dark, diff the
> pins and the CO5300 init table in `main/ui/display.c` (`s_co5300_init_cmds`) against that demo — it
> is the canonical source for this exact module.

## Backend URL (hardcoded to production)

The backend is **hardcoded** to `DEVICE_PROD_BACKEND_URL` = `wss://ac-api.autonomous.ai`
(`main/config_store.h`). Boot force-overrides whatever is in NVS with it (so already-provisioned
units auto-switch to prod), and the setup portal only collects **WiFi** — no URL/API-key field. The
REST base (`https://ac-api.autonomous.ai`) is derived from it. To point at a different backend, edit
that one `#define`. Ports default to **443** for `wss://`/`https://` (only plain `ws://`/`http://`
fall back to `:8085`).

## Build & flash

```bash
cd device/harness
idf.py set-target esp32s3
idf.py build
idf.py -p <PORT> flash monitor      # e.g. -p /dev/cu.usbmodem1101
```

- **TLS config lives in `sdkconfig.defaults`** (cert bundle + `CONFIG_MBEDTLS_EXTERNAL_MEM_ALLOC=y`,
  which puts mbedTLS's ~32KB-per-connection record buffers in PSRAM — the internal heap fragments and
  the persistent WSS fails `ssl_setup -0x7F00` otherwise). `sdkconfig` is a generated, gitignored
  artifact; if you change a Kconfig **choice** and it doesn't take, `rm sdkconfig` and rebuild so the
  defaults are re-applied.
- **Dev shortcut:** to bake WiFi creds and skip the portal, copy
  `main/provisioned_config.h.example` → `main/provisioned_config.h`, set `DEVICE_FORCE_CONFIG 1`, and
  fill in `DEVICE_WIFI_SSID`/`DEVICE_WIFI_PASS`. That file is gitignored. (The backend URL there is
  ignored — prod is hardcoded.)
- **Shipping OTA to fielded devices?** See [`RELEASE.md`](RELEASE.md) — bump `version.txt`, build,
  publish; devices self-pull (SHA-256 verified, rollback-protected).

## Pairing (first boot)

With no saved WiFi the device boots into **provisioning**:

1. The screen shows: join WiFi **`Interns-Setup`**, open **`http://192.168.100.1`**.
2. On your phone, join that open AP — a captive portal opens automatically.
3. Enter your **WiFi SSID / password** only (the backend is fixed to production).
4. Submit → the device saves WiFi to NVS and reboots, joins WiFi, then shows a **6-digit pairing
   code** on screen.
5. Enter that code in your Interns account on the web. The device polls, receives a device token
   (stored in NVS), resolves its bound agent, and switches to the **projects** screen.

**Re-pair / factory reset:** hold the **BOOT** button while powering on — the saved config is cleared
and the portal restarts. **Change WiFi without re-pairing:** if the saved network can't be joined, the
device reboots into the `Interns-Setup` portal; the pairing token is preserved.

## What you see & how you interact

- **Status bar** (top, always on): WiFi icon · `HH:MM` (SNTP, Vietnam UTC+7) · battery % / charging.
- **Projects tileview:** one tile per project; **swipe left/right** to switch (page dots at the
  bottom). Each tile shows the project name, a connection dot (green = commander WS up), and the
  latest event card. A dim yellow **"processing"** row shows while a turn is running.
- **Read full text:** tap an event card → full-screen scrollable reader; tap again to go back.
- **Voice (hold-to-talk):** press physical **button B (BOOT/GPIO0)** to start recording, press again
  to stop; a red mic button also appears while recording. Audio is buffered in PSRAM and sent over the
  commander WS after release (`voice_start` → PCM → `voice_end`); the backend transcribes and
  dispatches it as a new turn on the visible project. If a turn is already running, a `cancel` is sent
  first so your spoken instruction takes over.
- **STOP:** while the visible project is processing, a red square **STOP** button appears (same spot
  as the mic, mutually exclusive) — tap it to interrupt (cancel) the running turn.
- **Questions:** when the agent asks (AskUserQuestion), the device shows the options; pick with taps
  (single/multi-select) or **speak the answer**. The choice is sent back as a `question_response`.
- **Create project:** long-press on the projects screen (~5s) creates a new "Project N" and focuses it.
- **Sleep:** the panel turns off after 2 min idle (or double-tap to toggle); double-tap wakes it.
- **Auth failure:** if the very first commander connection is rejected (`1008`), the screen shows an
  "Auth failed" error; transient closes after a successful connect are healed by auto-reconnect.

## Message protocol (over the commander WS)

**Inbound** (backend → device), parsed in `commander_client.c`:

| type | meaning |
|------|---------|
| `connected` | commander stream ready (also confirms the OTA image as valid) |
| `commander_event` | curated event `{kind: say/act/ask/summary/done/error/processing, text}`, project-tagged, carries `dbSessionId` |
| `commander_question` | AskUserQuestion `{requestId, questions[]}` |
| `transcript` / `too_short` | STT result / clip-too-short for a spoken answer |
| `stopped` | ack for a `cancel` we sent → clears the project's processing status |

**Outbound** (device → backend): `cancel {payload:{sessionId}}` (interrupt a turn),
`question_response {payload:{requestId, sessionId, answers}}`, and the voice frames
`voice_start` / binary PCM / `voice_end`. Auth is the agent's api key carried in the
`Sec-WebSocket-Protocol` subprotocol (not the URL).

## How it maps to the backend

| Device | Backend |
|--------|---------|
| WS `wss://ac-api.autonomous.ai/api/commander-ws` (apiKey via subprotocol) | backend hub relay → agent-node commander channel |
| `POST /api/devices/code` + `/poll` | 6-digit pairing handshake → device token |
| `GET /api/devices/agent` (Bearer token) | resolve bound agent → `{agentId, apiKey}` |
| `agents_list` / `agent_create` / `agent_recent` WS RPCs | agent list / create / recent events (the old `/proxy/api/projects` REST path is gone) |

(OTA is **not** a backend endpoint — the device fetches the manifest + image straight from GCS; see below.)

## OTA updates

Dual-OTA partition table (`partitions.csv`: `ota_0`/`ota_1` + `otadata`; `nvs` kept at the old offset
so the token + saved WiFi survive the one-time USB flash to this layout). On boot and every ~6h the
device fetches a **public GCS manifest** (`DEVICE_OTA_METADATA_URL` in `config_store.h` →
`.../s3-autonomous-upgrade-3/harness/esp32/ota/metadata.json`), reads `metadata.commander.version`;
if it differs from the running image (`version.txt`, currently `0.1.2`), it streams the manifest's
`url` (a public GCS `.bin`) to the inactive slot over HTTPS (cert-bundle verified), **verifies
SHA-256**, sets it bootable, and reboots. A fresh OTA boots in PENDING_VERIFY and only confirms itself
(cancelling rollback) once the commander WS reconnects — a broken image auto-rolls back. Publish with
`scripts/upload-firmware.sh`; see [`RELEASE.md`](RELEASE.md).

## Source layout

```
main/
  app_main.c          boot state machine (provision → WiFi → pair → agent → projects); OTA + long-press hooks
  config_store.*      NVS config (WiFi + saved-networks list + token); DEVICE_PROD_BACKEND_URL
  provisioning.*      SoftAP + captive portal (WiFi-only) + DNS hijack
  wifi_sta.*          STA connect with backoff; RSSI / connected state
  pairing.*           6-digit device-code pairing loop
  http_api.*          REST: pairing, agent, projects, recent events; OTA manifest fetch (public GCS)
  commander_client.*  esp_websocket_client (wss, cert bundle) + cJSON parse → UI; cancel sender
  ota.*               esp_https_ota from GCS: version-gated, SHA-256 verified, rollback-protected
  audio_capture.*     I2S + ES7210 mic capture / ES8311 beep
  audio_client.*      record to PSRAM, stream PCM over the commander WS
  ptt.*               button-B hold-to-talk (debounced toggle, 30s watchdog)
  board/board_i2c.*   shared I2C master bus
  board/power.*       AXP2101 battery %, charging, PWR-key tap
  board/board_pins.h  GPIO map — VERIFY against the Waveshare demo
  ui/display.*        CO5300 QSPI panel (init table) + LVGL v9 port + idle sleep
  ui/touch.*          CST9217 → LVGL pointer indev; double-tap sleep/wake; long-press
  ui/ui_screens.*     LVGL screens: status bar, provisioning, pairing, connecting, error,
                      projects tileview, event reader, question screen; mic + STOP buttons
  ui/font_viet_20.c   generated Vietnamese-capable font
```

Managed components (pulled by the IDF Component Manager — see `main/idf_component.yml`): `lvgl/lvgl`,
`espressif/esp_lcd_co5300`, `waveshare/esp_lcd_touch_cst9217`, `espressif/esp_codec_dev`,
`espressif/esp_websocket_client` (pinned `~1.2.0`).
