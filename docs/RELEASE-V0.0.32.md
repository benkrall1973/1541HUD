# 1541HUD V0.0.32 Promotion Record

## Status

V0.0.32 is the promoted release line derived from the hardware-tested V0.0.32-RC1 behavior.

The RC1 integration was exercised successfully on real Commodore 1541 hardware with the corrected GUI parser. Observed together were HOME anchoring, track/head/motor/write-protect/density state, physical-header RPM, live sector, recent-sector FIFO, raw PB7 SYNC/sec, and SYNC/revolution estimation.

The final V0.0.32 source promotion intentionally changes release identity only. It preserves the selected hardware-tested runtime behavior from the RC1 path and keeps the T0.x and RC1 sources unchanged for provenance.

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

## Promotion rule

The final V0.0.32 build should be built once from the promoted source, its SHA-256 hashes recorded, and the exact UF2 given a short real-hardware sanity test before the `v0.0.32` tag is treated as the released hardware-tested artifact.

No new functionality is introduced during this final identity promotion.
