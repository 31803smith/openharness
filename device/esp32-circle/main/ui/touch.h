// CST9217 capacitive touch → LVGL pointer indev (enables tileview swipe).
#pragma once

#include <stdbool.h>
#include <stdint.h>

// Initialize I2C + CST9217 + register an LVGL pointer indev. Call after lv_init().
// Tolerant: logs and returns on failure (display still works, just no touch).
void touch_init(void);


// Monotonic generation bumped once for every physical touch press. Background rendering, voice, and
// programmatic display activity do not affect it, so callers can cheaply detect real user interaction.
uint32_t touch_activity_generation(void);
