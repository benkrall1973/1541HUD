/*
 * 1541HUD T0.0.17 - OneROM v0.7.2 native logging experiment
 *
 * Purpose:
 *   Prove the v0.7.2 ORA_LOG_OPEN_WRITE / ORA_LOG_WRITE application-log path
 *   without changing the hardware-proven T0.0.16 passive monitor logic.
 *
 * Safety / scope:
 *   - The complete T0.0.16 monitor implementation is compiled in unchanged.
 *   - PIO/DMA capture, UC2 /CS2 qualification, GPIO24 SYNC, mailbox layout,
 *     USB CDC telemetry, track/HOME/WP/density/HDRPHY/RPM/SYNC decode and
 *     passive-UB4 protection are untouched.
 *   - This wrapper only emits one startup record through OneROM's v0.7.2
 *     application log channel, then permanently hands control to T0.0.16.
 *
 * Note:
 *   Existing STATE/SYNC telemetry intentionally continues to identify itself
 *   as T0.0.16 because that text belongs to the preserved baseline.  The new
 *   native-log record is the T0.0.17 identity for this experiment.
 */

#include "plugin.h"

/* Compile the proven baseline implementation under a private entry-point name,
 * and suppress its plugin header.  This keeps the baseline source byte-for-byte
 * untouched while allowing this file to provide the T0.0.17 plugin header and
 * a very small wrapper entry point.
 */
#define drivehud_probe_main drivehud_probe_t016_main
#undef ORA_DEFINE_USER_PLUGIN
#define ORA_DEFINE_USER_PLUGIN(fn, major, minor, patch, build, min_fw_major, min_fw_minor, min_fw_patch)
#include "1541hud_probe_t016_v072_baseline.c"
#undef ORA_DEFINE_USER_PLUGIN
#undef drivehud_probe_main

ORA_DEFINE_PLUGIN_HEADER(
    ORA_PLUGIN_TYPE_USER,
    drivehud_probe_main,
    0, 0, 17, 0,
    0, 7, 2
);

static const char t017_log_name[] = "1541HUD";
static const char t017_start_record[] =
    "1541HUD T0.0.17 v0.7.2 native LOG_WRITE startup test\r\n";

void drivehud_probe_main(
    ora_lookup_fn_t ora_lookup_fn,
    ora_plugin_type_t plugin_type,
    const ora_entry_args_t *entry_args
) {
    ora_log_open_write_fn_t log_open =
        (ora_log_open_write_fn_t)ora_lookup_fn(ORA_ID_LOG_OPEN_WRITE);
    ora_log_write_fn_t log_write =
        (ora_log_write_fn_t)ora_lookup_fn(ORA_ID_LOG_WRITE);
    ora_err_log_fn_t err_log =
        (ora_err_log_fn_t)ora_lookup_fn(ORA_ID_ERR_LOG);

    if (log_open != NULL && log_write != NULL) {
        ora_result_t rc = log_open(ORA_LOG_CHANNEL_0, t017_log_name);
        if (rc == ORA_RESULT_OK) {
            (void)log_write(
                ORA_LOG_CHANNEL_0,
                t017_start_record,
                (uint32_t)(sizeof(t017_start_record) - 1u)
            );
        } else if (err_log != NULL) {
            err_log("1541HUD T0.0.17 LOG_OPEN_WRITE failed rc=%u\n", (unsigned)rc);
        }
    } else if (err_log != NULL) {
        err_log("1541HUD T0.0.17 v0.7.2 logging API lookup failed\n");
    }

    /* Never returns during normal operation. */
    drivehud_probe_t016_main(ora_lookup_fn, plugin_type, entry_args);
}
