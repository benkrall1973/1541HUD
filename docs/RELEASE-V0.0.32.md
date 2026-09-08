# 1541HUD V0.0.32 Promotion Record

## Status

V0.0.32 is the hardware-tested stable release derived from the hardware-tested V0.0.32-RC1 behavior.

The RC1 integration was exercised successfully on real Commodore 1541 hardware with the corrected GUI parser. Observed together were HOME anchoring, track/head/motor/write-protect/density state, physical-header RPM, live sector, recent-sector FIFO, raw PB7 SYNC/sec, and SYNC/revolution estimation.

The final V0.0.32 source promotion intentionally changed release identity only. It preserved the selected hardware-tested runtime behavior from the RC1 path and kept the T0.x and RC1 sources unchanged for provenance.

The exact final V0.0.32 UF2 and final V0.0.32 GUI were then sanity-tested successfully on real Commodore 1541 hardware. The final release therefore passed both build validation and real-hardware validation.

## Final canonical paths

- Builder: `1541hud/Build-1541HUD-V0032.ps1`
- GUI: `1541hud/gui/1541HUD_V0.0.32.py`
- Current build wrapper: `1541hud/Build-1541HUD-Current.ps1`
- Current GUI launcher: `1541hud/Run-1541HUD-Current.ps1`

The final builder generates and preserves:

- `1541HUD_OneROM_V0.0.32.bin`
- `1541HUD_OneROM_V0.0.32.uf2`
- `1541hud_probe_v0032_SOURCE.c`
- `usb_main_v0032_SOURCE.c`

## Final build validation

The final V0.0.32 build completed successfully from the promoted source on the established Windows + WSL build environment.

Artifacts:

| Artifact | Size | SHA-256 |
|---|---:|---|
| `1541HUD_OneROM_V0.0.32.bin` | 204800 bytes | `4C2FECA86D06E178E0332B1558C4F03F398C8E7137A6C80F04BE440FCB96DD8B` |
| `1541HUD_OneROM_V0.0.32.uf2` | 409600 bytes | `52AE4F8DA9720E316BA8A3FFF8CF10A4CF9DE325C8EC3588B49BE8394BF0CE1B` |
| `1541hud_probe_v0032_SOURCE.c` | 22159 bytes | `757713C40E9598F2F140D50ABA8EA30BDD85EA390C1D1C33D7D230F29EA8C031` |
| `usb_main_v0032_SOURCE.c` | 18214 bytes | `2831BC3E5375CD103D5B7497066BDD8FFCDCB69416DB59BFCFA29B7E773AD977` |

The build also reproduced the preserved T0.0.15 source baseline hashes before generating the final V0.0.32 source copies.

## Hardware validation

The exact final V0.0.32 build was flashed and tested on the real drive. The final GUI reported the V0.0.32 identity and the integrated monitor functions operated normally, including HOME anchoring, track/mechanism state, density, RPM, sector, recent-sector FIFO, SYNC/sec, and SYNC/revolution telemetry.

This completed the final release gate.

## Post-release direction

Future work is intentionally outside V0.0.32. Planned development includes porting the desktop GUI to an LCD touchscreen and separately developing operator controls for IEC device-address changing and write-protect override.

No new functionality was introduced during the final identity promotion.