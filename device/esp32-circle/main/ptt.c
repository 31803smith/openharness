#include "ptt.h"
#include "ui/ui_screens.h"
#include "ui/display.h"
#include "board/power.h"
#include "board/board_pins.h"
#include "audio_client.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_timer.h"
#include "esp_log.h"

static const char *TAG = "ptt";
#define POLL_MS      100               // AXP2101 PWR-key poll cadence (latency only — the key event latches)

// Button A (the PWR key, wired to the AXP2101 PWRON pin — read over I2C, not a GPIO) toggles the SCREEN
// on/off. Voice is gesture-driven now (double-tap starts, a tap stops — see touch.c), so this key no
// longer touches voice. A LONG press restarts the device in AXP2101 hardware and never reaches us.
static void ptt_task(void *arg)
{
    // BOOT button (GPIO0, active-low) → interrupt the running turn (replaces the on-screen STOP).
    gpio_config_t bcfg = {
        .pin_bit_mask = 1ULL << BSP_BOOT_BUTTON,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&bcfg);
    int boot_prev = 1;       // released (active-low: 1 = up, 0 = pressed)

    while (1) {
        if (power_take_pwrkey_tap()) {                 // one short press of button A (PWR) → toggle screen
            // Hold the LVGL lock: display_sleep/wake touch LVGL timers + the panel, and normally run on
            // the LVGL task; the recursive mutex serialises this ptt-task call with it.
            display_lock();
            if (display_is_asleep()) { ESP_LOGI(TAG, "PWR tap → screen ON");  display_wake(); }
            else                     { ESP_LOGI(TAG, "PWR tap → screen OFF"); display_sleep(); }
            display_unlock();
        }

        // BOOT button: on a fresh press (falling edge), interrupt the visible project's running turn.
        int boot_now = gpio_get_level(BSP_BOOT_BUTTON);
        if (boot_prev == 1 && boot_now == 0) {
            if (display_is_asleep()) { display_lock(); display_wake(); display_unlock(); }
            ESP_LOGI(TAG, "BOOT press → back / stop turn");
            ui_boot_pressed();
        }
        boot_prev = boot_now;

        vTaskDelay(pdMS_TO_TICKS(POLL_MS));
    }
}

void ptt_start(void)
{
    // Priority 3 — below the LVGL task (4) so button polling never preempts UI rendering.
    xTaskCreate(ptt_task, "ptt", 4096, NULL, 3, NULL);
}
