#include "touch.h"

#include "cable_client.h"
#include "board_pins.h"
#include "board_i2c.h"
#include "display.h"
#include "ui_screens.h"   // ui_swipe_begin/end for the circular edge-swipe
#include "driver/i2c_master.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_touch_cst9217.h"
#include "esp_log.h"
#include "lvgl.h"
#include <stdlib.h>

static const char *TAG = "touch";
static esp_lcd_touch_handle_t s_tp;

// How far a finger may drift and still count as "held still". Shared by the near-still TAP test and the
// GOAL hold — it outlived the create-project long-press that introduced it.
#define LONG_MOVE_PX  30

#define DOUBLE_TAP_MS 500   // two taps within this window (and close in position) = a double-tap. Also the
                            // delay before a single tap opens the detail reader — 500ms so a (slightly slow)
                            // double-tap-to-voice is recognised first instead of the 1st tap firing detail.
// Single writer (LVGL touch task), lock-free readers. A 32-bit aligned load/store is atomic on ESP32-S3;
// wraparound is harmless because consumers compare generations for equality only.
static volatile uint32_t s_activity_gen;

uint32_t touch_activity_generation(void)
{
    return s_activity_gen;
}

// Edge-triggered double-tap detector. Call EVERY read (to track the press edge); returns true once
// on the second of two quick, nearby taps. Shared by both wake (asleep) and sleep (awake).
static bool double_tap(bool pressed, uint16_t x, uint16_t y)
{
    static bool prev;
    static uint32_t last_ms;
    static int16_t lx, ly;
    bool hit = false;
    if (pressed && !prev) {                          // rising edge = a tap
        uint32_t now = lv_tick_get();
        int dx = (int)x - lx, dy = (int)y - ly;
        if (now - last_ms < DOUBLE_TAP_MS && dx * dx + dy * dy < 80 * 80) {
            hit = true; last_ms = 0;                 // consumed — a 3rd tap won't re-trigger
        } else {
            last_ms = now; lx = x; ly = y;
        }
    }
    prev = pressed;
    return hit;
}

// Edge-triggered swipe/tap detector. Call EVERY read (awake only). On press-down it snapshots the tile
// position (ui_swipe_begin); on release it classifies the gesture: a mostly-horizontal drag → ui_swipe_end
// (circular wrap); a short near-still press is a TAP → STOP voice if we're recording (voice is
// gesture-driven: double-tap starts, tap stops). A mostly-vertical drag is no longer classified at all —
// it is reported to the computer as it happens, see the touchpad block below.
// ── the dial as a touchpad ──────────────────────────────────────────────────────────────────────────
// A vertical drag is reported to the computer WHILE THE FINGER IS DOWN, in pieces, so the window scrolls
// under the hand instead of jumping when it lifts. What goes out is travel since the last report — the
// dial cannot know how tall the far side is, so the side that owns the scrollback does the arithmetic.
#define SCROLL_MIN_PX   8      // report after this much travel...
#define SCROLL_EVERY_MS 50     // ...or this long, whichever comes first
// Ceiling on the reported speed, px/s. One jittery sample across a 4ms window reads as thousands of pixels
// a second; with no lid that lands on the far side as a fling to the end of the scrollback. ~6000 is well
// past anything a hand does on a 466px face and still finite.
#define SCROLL_V_MAX    6000

#define SWIPE_MIN_PX 55
#define TAP_MAX_MS   700   // a near-still press shorter than this = a tap (not a hold/long-press)
// Home gesture: an upward swipe must START at/below this y (panel is 466 tall) to count as a bottom-edge
// swipe → Overview. Bottom ~14% band; well below where mid-tile "swipe-up = open detail" gestures begin.
#define BOTTOM_EDGE_PX 400
// On the detail reader the ONLY non-scroll vertical gesture is a tight bottom-edge up-swipe → Overview, so it
// uses a much narrower band than the carousel screens: a swipe that STARTS within the bottom ~20px (panel 466).
#define READER_HOME_EDGE_PX 446
// A single tap toggles the detail reader (open on projects / close on the reader), but a double-tap
// starts voice. They're indistinguishable until the double-tap window passes, so DEFER the tap's action
// by DOUBLE_TAP_MS and cancel it if a 2nd tap arrives (that's a start-voice). A tap while RECORDING is
// NOT deferred — it stops immediately (see rec_at_down below).
static bool s_tap_pending;
static uint32_t s_tap_pending_ms;
// Where the press landed. The tap is deferred past the double-tap window, by which time the finger has
// gone, so the point has to be carried with it — ui_tap uses it to decide what was actually touched.
static int16_t s_tap_x, s_tap_y;
// GOAL gesture: a still hold ≥2s (awake, not already recording) starts a GOAL voice command.
// It "consumes" the press: swallows the rest so it lands as no UI tap.
#define GOAL_HOLD_MS 2000
static bool s_goal_swallow;
// Swallow all input until the finger lifts — set after a wake tap / double-tap-voice / goal-hold so the
// consumed gesture doesn't also drive the UI. File-scope so swipe_track can be gated off while it's set
// (otherwise swipe_track starts mid-gesture on the read after wake and classifies the release as a tap →
// stray "open detail" on the very tap that woke the screen).
static bool s_swallow_until_release;

static int      s_scroll_acc;    // travel not yet reported, device px (positive = down the glass)
static uint32_t s_scroll_at;     // when the last report went out
static int      s_scroll_v;      // smoothed speed, px/s, signed like the travel
static bool     s_scroll_live;   // is THIS stroke being reported? decided once, at press-down
// Everything this stroke has actually PUT ON THE WIRE, signed. Only for the line logged at the lift: the
// travel leaves in windows during the drag, so the `up` frame carries a remainder that is almost always
// zero — which made the first version of that line say `dy=0` for every stroke ever made and prove
// nothing about which way it went.
static int      s_scroll_sent;

// Fold one reporting window into the smoothed speed.
//
// MEASURED HERE AND NOWHERE ELSE, because this is the only place the hand's speed exists. By the time a
// frame has been framed, crossed the cable, been queued and decoded, the gap between arrivals describes
// the link rather than the finger.
//
// The window's own length is what makes a resting finger decay to nothing: a window with no travel in it
// is a real measurement of zero, so a hand that stops before it lifts is not thrown.
static void scroll_measure(int px, uint32_t ms)
{
    if (!ms) return;
    int inst = px * 1000 / (int)ms;
    if (inst >  SCROLL_V_MAX) inst =  SCROLL_V_MAX;
    if (inst < -SCROLL_V_MAX) inst = -SCROLL_V_MAX;
    // Weighted 3:2 toward the newest window: enough smoothing that one bad sample cannot define a fling,
    // little enough that the flick at the END of the stroke is what gets measured — which is the whole of
    // what a person means by "how fast I swiped".
    s_scroll_v = (inst * 3 + s_scroll_v * 2) / 5;
}

// Close a stroke that is still open, without a throw. For the one thing that can steal a finger mid-flight
// (a voice turn coming up under it) — a drag left open on the far side holds its list and makes it ignore
// the mouse.
static void scroll_abort(void)
{
    if (!s_scroll_live) return;
    cable_client_send_scroll(CABLE_SCROLL_UP, 0, 0);
    s_scroll_live = false;
}
// Which way this hand expects a drag to move the far side's scrollback (Settings › Scroll).
//
// SIGNED HERE, at the one place the report leaves the device. Nothing downstream — the daemon, the window,
// the terminal — learns that the setting exists, which is the point: a preference two sides both have to
// hold is a preference they can disagree about, and this one would show up as a scroll that goes the wrong
// way only on some screens.
// THE SIGNS WERE INVERTED once, on the reading that the labels were swapped — and put back the other way
// again (owner, 2026-09-14: "đảo ngược logic natural vs reversed, text thì keep đúng hết rồi"): with the
// dial in hand, "Natural" is the text following the finger, which is the sign this now returns for it.
// Only the arithmetic moves — the row still reads Natural ⇄ Reversed, the NVS key is untouched, and the
// default is still Natural.
static int scroll_sign(void) { return ui_scroll_is_reversed() ? -1 : 1; }

static void swipe_track(bool pressed, uint16_t x, uint16_t y)
{
    static bool prev;
    static int sx, sy, lx, ly;
    static uint32_t t0;
    static bool rec_at_down;   // was a turn recording when THIS press began? (see the tap-to-stop below)
    if (pressed && !prev) {                 // press down
        sx = lx = x; sy = ly = y; t0 = lv_tick_get();
        rec_at_down = ui_voice_is_recording();
        ui_swipe_begin();
        // DECIDED ONCE, HERE, and not re-asked for the rest of the stroke. A gesture that is a scroll must
        // stay a scroll to its end even if the screen changes underneath it, or the far side is left
        // holding a drag that never closes.
        //
        // NOT for a stroke that began at the bottom edge: that one is the home swipe, and scrolling the
        // computer on the way to leaving the screen is not what the hand meant.
        s_scroll_acc = 0;
        s_scroll_at = t0;
        s_scroll_v = 0;
        s_scroll_sent = 0;
        s_scroll_live = ui_scroll_reportable()
                        && sy < (ui_reader_is_open() ? READER_HOME_EDGE_PX : BOTTOM_EDGE_PX);
        if (s_scroll_live) cable_client_send_scroll(CABLE_SCROLL_DOWN, 0, 0);
    } else if (pressed) {                   // dragging → remember the latest point
        s_scroll_acc += y - ly;
        lx = x; ly = y;
        // Voice came up under the finger and owns the surface now. End the stroke rather than leaving the
        // far side holding a drag.
        if (s_scroll_live && ui_voice_is_active()) scroll_abort();
        if (s_scroll_live && (abs(s_scroll_acc) >= SCROLL_MIN_PX
                              || lv_tick_elaps(s_scroll_at) >= SCROLL_EVERY_MS)) {
            scroll_measure(s_scroll_acc, lv_tick_elaps(s_scroll_at));
            // A window with no travel still counts toward the speed above (that is what lets a resting
            // finger decay), but there is nothing to send.
            if (s_scroll_acc) {
                cable_client_send_scroll(CABLE_SCROLL_MOVE, scroll_sign() * s_scroll_acc, 0);
                s_scroll_sent += scroll_sign() * s_scroll_acc;
            }
            s_scroll_acc = 0;
            s_scroll_at = lv_tick_get();
        }
    } else if (!pressed && prev) {          // release
        if (s_scroll_live) {
            // Whatever is left travels first, then the throw. Dropping it would lose up to SCROLL_MIN_PX at
            // the very end of a stroke, which is exactly where a hand is aiming.
            scroll_measure(s_scroll_acc, lv_tick_elaps(s_scroll_at));
            // The throw is signed with the drag. Flipping only the travel would send the flick off in the
            // opposite direction to the finger that made it.
            cable_client_send_scroll(CABLE_SCROLL_UP, scroll_sign() * s_scroll_acc, scroll_sign() * s_scroll_v);
            s_scroll_sent += scroll_sign() * s_scroll_acc;
            // One line per STROKE, at the lift — the proof of which way this went. A setting whose whole
            // effect happens on another computer is otherwise judged by eye alone, and "it didn't work"
            // and "it worked and I expected the other way" look identical from here.
            //
            // The TOTAL, not the remainder: positive is a finger travelling DOWN the glass, so `natural`
            // and `reversed` on the same stroke must print opposite signs. That is the whole claim this
            // setting makes, in one line, per swipe.
            ESP_LOGI(TAG, "scroll: total=%+d px v=%+d (%s)", s_scroll_sent,
                     scroll_sign() * s_scroll_v, ui_scroll_is_reversed() ? "reversed" : "natural");
            s_scroll_live = false;
        }
        int dx = lx - sx, dy = ly - sy;
        // During a voice turn the overlay owns the screen: ONLY tap-to-stop is allowed — swiping must not
        // switch tiles / open detail / jump home underneath the overlay. So gate every swipe action off while
        // voice is active and fall straight through to the tap branch (which stops the recording).
        bool voice = ui_voice_is_active();
        // The DETAIL READER has its own tight gesture set (the rest is native vertical scroll):
        //   • up-swipe from the bottom ~20px → Overview   • horizontal swipe → back to the agent screen
        // Everything else on the reader (mid-screen vertical drag, taps) is left to LVGL scroll / does nothing.
        // (double-tap = voice and the ≥2s hold = goal are handled in touch_read, independent of this.)
        bool reader = ui_reader_is_open();
        int home_edge = reader ? READER_HOME_EDGE_PX : BOTTOM_EDGE_PX;
        // HOME gesture: an upward swipe that STARTED at the bottom edge → jump to Overview. (y grows downward;
        // the driver already applies the panel mirror, so sy near y_max = the physical bottom.)
        if (!voice && sy >= home_edge && dy < -SWIPE_MIN_PX && abs(dy) > abs(dx))
            ui_home_overview();
        else if (!voice && (dx > SWIPE_MIN_PX || dx < -SWIPE_MIN_PX) && abs(dx) > abs(dy))
            ui_swipe_end(dx > 0 ? 1 : -1);         // reader → back to the agent; carousel screens → wrap next/prev
        // A vertical drag is NOT classified here any more — it went out as it happened (above). One
        // gesture cannot mean two things: while it also opened the detail reader, every scroll ended by
        // opening a screen nobody asked for. Tapping the recap card opens it, which is the route it kept.
        else if (abs(dx) < LONG_MOVE_PX && abs(dy) < LONG_MOVE_PX
                 && lv_tick_elaps(t0) < TAP_MAX_MS) {   // near-still TAP
            // A tap while RECORDING always stops the voice — on EVERY screen, including the reader (this is the
            // only touch way to end a turn started by double-tap there). The deferred open/close tap, however,
            // is disabled on the reader (it has no single-tap action).
            // rec_at_down alone is not enough: touch_read starts a voice turn on the SECOND tap of a
            // double-tap, before this handler samples it, so the very press that began the turn arrives
            // here looking like a press during one — and stops it instantly. The local mic path hid this
            // because its indicator state is set asynchronously, a few frames later; the cabled path sets
            // it inline and exposed it. Compare start times: a turn that began at or after this press is
            // this press's own doing and must not be stopped by its release.
            if (rec_at_down && (int32_t)(ui_voice_start_tick() - t0) < 0) ui_voice_stop();
            else if (!reader) { s_tap_pending = true; s_tap_pending_ms = t0; s_tap_x = sx; s_tap_y = sy; }
        }
        // (a swipe while recording matches none of the above → ignored; only a still tap stops the voice)
    }
    prev = pressed;
}

// LVGL reads the latest touch point. Marshalled by LVGL's own task; reading the
// CST9217 over I2C from here is fine (LVGL task holds no conflicting lock).
static void touch_read(lv_indev_t *indev, lv_indev_data_t *data)
{
    static bool activity_prev;
    (void)indev;
    if (!s_tp) { data->state = LV_INDEV_STATE_RELEASED; return; }
    uint16_t x = 0, y = 0, strength = 0;
    uint8_t cnt = 0;
    esp_lcd_touch_read_data(s_tp);
    bool pressed = esp_lcd_touch_get_coordinates(s_tp, &x, &y, &strength, &cnt, 1) && cnt > 0;
    if (pressed && !activity_prev) s_activity_gen++;
    activity_prev = pressed;

    // A touch that STARTS on one of Overview's two round voice actions belongs to that LVGL button until
    // release. Feed `false` to the screen-wide recognizers for the whole gesture, but keep the real pointer
    // state for LVGL below. This prevents Voice-button holds/double-taps from also firing the hidden global
    // Goal/Voice gestures. A drag can still leave the button and scroll the carousel through LVGL normally.
    static bool action_prev, action_capture;
    if (pressed && !action_prev) {
        action_capture = ui_action_hit(x, y);
        if (action_capture) s_tap_pending = false;
    }
    bool action_touch = action_capture && (pressed || action_prev);
    bool gesture_pressed = pressed && !action_touch;
    if (!pressed && action_prev) action_capture = false;
    action_prev = pressed;

    bool dbl = double_tap(gesture_pressed, x, y);     // call every read to keep edge tracking valid

    // The notification zone OWNS its gestures — like the brightness catcher — so a pull-down or a list
    // scroll can never leak into the voice/detail layer. Capture the whole gesture from press-down when
    // the drawer is already OPEN, or when a press starts in the top pull-zone (ui_notif_pull_zone_px() —
    // narrow on agent tiles so the Mode/Model chips still get taps, full band on Overview/Settings/Machines).
    // While captured:
    // feed LVGL only if the drawer is open (so the list scrolls + rows/background tap); otherwise swallow
    // (a top-zone pull must not drive the projects UI underneath). On release, decide open/close.
    {
        static bool ndrag, nprev; static int ndy0, ndyl;
        bool ncap = false;
        if (pressed && !nprev) {
            // Not on the reader: notifications aren't openable there, and swallowing the top band would break
            // scrolling from the top of the text. The reader owns its whole surface for vertical scroll.
            // Not under the switcher either: it covers the whole face, and its top rows are inside this
            // band — captured, they would be untappable in exactly the list you opened to tap.
            //
            // A chooser wheel is the same shape of thing and was the same bug: its close X sits at the
            // top of the face, inside a 90px band this would otherwise swallow whole, so the one control
            // that leaves the screen could never be pressed. A modal chooser also has no business
            // offering a pull-to-notifications on top of itself.
            ndrag = !display_is_asleep() && !ui_reader_is_open() && !ui_switch_is_open() &&
                    !ui_picker_is_open() &&
                    (ui_notif_is_open() || y < ui_notif_pull_zone_px());
            ndy0 = ndyl = y; ncap = ndrag;
        } else if (pressed && ndrag) {
            ndyl = y; ncap = true;
        } else if (!pressed && nprev && ndrag) {          // release of a captured gesture
            int d = ndyl - ndy0;
            if (ui_notif_is_open()) { if (d < -SWIPE_MIN_PX) ui_notif_swipe_up(); }  // up → close (only if list at top)
            // Pull down from the top → the NOTIFICATIONS (owner, 2026-09-14). The gesture opened the
            // agent switcher for a while; the switcher is retired from the glass now that the carousel
            // walks the window's swarm and the swarm line above the name picks between swarms, so the
            // pull-down goes back to the list it first opened. A TAP in the band opens the same list —
            // the bell is a button, but this band swallows every press that starts inside it, and the
            // bell sits INSIDE it.
            else if (d > SWIPE_MIN_PX || (d > -SWIPE_MIN_PX && d < SWIPE_MIN_PX)) ui_notif_open();
            ndrag = false; ncap = true;
        }
        nprev = pressed;
        if (ncap) {
            if (ui_notif_is_open() && pressed) { data->point.x = x; data->point.y = y; data->state = LV_INDEV_STATE_PRESSED; }
            else data->state = LV_INDEV_STATE_RELEASED;   // closed-zone pull → swallow; or released
            return;
        }
    }

    // Swipes + tap-to-stop-voice. Skip while swallowing a consumed gesture (wake / voice / goal) so the
    // release of that gesture isn't misread as a fresh tap.
    // ...and not under the agent picker, whose rows are LVGL's to dispatch: swipe_track would read a row
    // tap as the tap that opens the detail reader, and a scroll of the list as a carousel swipe, both
    // happening to the tile UNDERNEATH the overlay.
    if (!display_is_asleep() && !s_swallow_until_release && !s_goal_swallow && !ui_switch_is_open())
        swipe_track(gesture_pressed, x, y);

    // GOAL: a still hold ≥3s (awake, not already recording) → start a GOAL voice command. Consumes the press
    // (swallow the rest so it doesn't land as a UI tap on release).
    {
        static bool gprev; static uint32_t gt0; static int16_t gsx, gsy; static bool gmoved, gfired;
        if (gesture_pressed && !gprev) { gt0 = lv_tick_get(); gsx = x; gsy = y; gmoved = false; gfired = false; }
        else if (gesture_pressed && !gfired) {
            int dx = (int)x - gsx, dy = (int)y - gsy;
            if (dx * dx + dy * dy > LONG_MOVE_PX * LONG_MOVE_PX) gmoved = true;
            if (!gmoved && !display_is_asleep() && !ui_voice_is_active() && lv_tick_elaps(gt0) >= GOAL_HOLD_MS) {
                gfired = true;
                s_goal_swallow = true; // swallow until the finger lifts (no stray UI tap)
                ui_voice_start_goal();
            }
        }
        gprev = gesture_pressed;
    }

    // Resolve a deferred single tap. Anchored to the PRESS and only fires once the double-tap window has
    // passed — so a double-tap always cancels it first. Extra guard: skip if a turn just started (voice).
    if (dbl) s_tap_pending = false;
    else if (s_tap_pending && lv_tick_elaps(s_tap_pending_ms) >= DOUBLE_TAP_MS) {
        s_tap_pending = false;
        if (!display_is_asleep() && !ui_voice_is_active()) ui_tap(s_tap_x, s_tap_y);
    }

    // After a double-tap starts voice, the finger is usually STILL down. Keep swallowing until it lifts,
    // so the two taps don't also land as UI presses (a stray tile/settings click).
    if (s_swallow_until_release || s_goal_swallow) {
        if (pressed) { data->state = LV_INDEV_STATE_RELEASED; return; }
        s_swallow_until_release = false;
        s_goal_swallow = false;   // finger lifted → goal-hold press fully consumed
    }

    if (display_is_asleep()) {
        // Asleep: a SINGLE tap WAKES the screen (Button A also wakes/sleeps). Wake on press-down and swallow
        // until the finger lifts so the waking tap doesn't fall through as a UI tap / start voice.
        if (pressed) { display_wake(); s_swallow_until_release = true; }
        data->state = LV_INDEV_STATE_RELEASED;
        return;
    }

    // During a voice turn the overlay owns the whole screen: never forward the touch to LVGL, so a swipe can't
    // natively scroll the tileview to Settings and a stop-tap can't land on a Wifi/passcode row underneath.
    // tap-to-stop + swipe suppression already ran in swipe_track above (raw coords) — swallow everything else.
    if (ui_voice_is_active()) { data->state = LV_INDEV_STATE_RELEASED; return; }

    // Awake: a double-tap used to START voice here (owner, 2026-09-14: "bỏ double tap để voice"). The
    // Voice button on the tile and on the Overview is the way in now; a double-tap while awake is two
    // taps, and lands as two taps. Stopping is still a single tap (swipe_track).
    (void)dbl;

    if (pressed) {
        data->point.x = x;
        data->point.y = y;
        data->state = LV_INDEV_STATE_PRESSED;
    } else {
        data->state = LV_INDEV_STATE_RELEASED;
    }
}

void touch_init(void)
{
    // Shared I2C master bus (touch + audio codecs live on the same bus).
    i2c_master_bus_handle_t bus = board_i2c_get();
    if (!bus) {
        ESP_LOGW(TAG, "shared i2c bus unavailable — touch disabled");
        return;
    }

    esp_lcd_panel_io_handle_t tp_io = NULL;
    esp_lcd_panel_io_i2c_config_t io_cfg = ESP_LCD_TOUCH_IO_I2C_CST9217_CONFIG();
    io_cfg.scl_speed_hz = BSP_I2C_FREQ_HZ;
    if (esp_lcd_new_panel_io_i2c(bus, &io_cfg, &tp_io) != ESP_OK) {
        ESP_LOGW(TAG, "touch panel io failed — touch disabled");
        return;
    }

    esp_lcd_touch_config_t tp_cfg = {
        .x_max = 466,
        .y_max = 466,
        .rst_gpio_num = BSP_TOUCH_RST,
        .int_gpio_num = BSP_TOUCH_INT,
        // The CST9217 is mounted 180° relative to the CO5300 on this board, so BOTH axes are
        // reversed vs the display (horizontal swipe and vertical scroll/taps). Mirror X and Y.
        .flags = { .swap_xy = 0, .mirror_x = 1, .mirror_y = 1 },
    };
    if (esp_lcd_touch_new_i2c_cst9217(tp_io, &tp_cfg, &s_tp) != ESP_OK) {
        ESP_LOGW(TAG, "CST9217 init failed — touch disabled");
        s_tp = NULL;
        return;
    }

    lv_indev_t *indev = lv_indev_create();
    lv_indev_set_type(indev, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(indev, touch_read);
    ESP_LOGI(TAG, "CST9217 touch ready");
}
