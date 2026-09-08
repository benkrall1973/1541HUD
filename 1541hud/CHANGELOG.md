# 1541HUD Changelog

This changelog tracks 1541HUD/DriveHUD project releases. The repository root `CHANGELOG.md` is retained as upstream OneROM history.

## v0.0.32 - 2026-09-07

Current stable hardware-tested release.

V0.0.32 integrates the selected hardware-tested T0.x development work under one release identity and preserves the experimental sources for provenance.

Included in V0.0.32:

- `/CS2`-only UC2 decode from T0.0.14; the former CS1 monitor wire is no longer required.
- Direct UC2 PB7/SYNC monitoring on GPIO24 from T0.0.15.
- Physical-header RPM measurement from T0.0.11.
- Live last-decoded physical sector display from T0.0.12.
- 10-entry recent-sector FIFO from T0.0.13.
- Four-zone SYNC/RPM validation results from T0.0.16.
- RPM seek/reacquisition diagnosis from T0.0.17.
- Last-good RPM hold, qualified reacquisition, and clean post-seek SYNC report handling from T0.0.18.
- Unified `V0.0.32` telemetry/build identity.
- Explicit GUI warning when absolute track position has not yet been HOME-anchored after a ROM change/reset.
- Dual-OneROM and complete passive-monitor wiring documentation.

The final V0.0.32 firmware and GUI were built from the promoted source and then sanity-tested successfully on real Commodore 1541 hardware. Confirmed together in the final GUI were HOME anchoring, track/head/motor/write-protect/density state, fresh physical-header RPM, live sector, populated recent-sector FIFO, raw PB7 SYNC/sec, and SYNC/revolution estimation.

Final build hashes are recorded in `docs/RELEASE-V0.0.32.md`.

Planned post-V0.0.32 work includes porting the desktop GUI to an LCD touchscreen and separately developing operator controls for IEC device-address changing and write-protect override. These are future control features and are not part of the passive V0.0.32 release.

## V0.0.32-RC1 - hardware-tested release candidate

Integrated release-candidate line built from the hardware-proven V0.0.30/V0.0.31 baseline plus the selected T0.x development results.

The exact RC1 firmware and integrated GUI were exercised successfully on real Commodore 1541 hardware. A GUI telemetry parser regression found during first integration was corrected without changing the flashed firmware, after which the complete telemetry display was restored.

RC1 was then promoted to final V0.0.32 with release-identity changes only.

## v0.0.31 - 2026-09-05

1541HUD project rename baseline.

- Renamed the public project from DriveHUD to 1541HUD.
- Preserved the proven V0.0.30 acquisition and USB mailbox protocol behavior.
- Added canonical 1541HUD source paths, GUI entry point, build script, and documentation.
- Preserved the immutable `v0.0.30` hardware-proven tag.
- Confirmed CI and 1541HUD source sanity checks on the released commit.
- Established `main` as the stable V0.0.31 public branch baseline.

## v0.0.30 - 2026-09-05

Hardware-proven DriveHUD baseline.

Confirmed behavior includes:

- Track and half-track display
- Diagnostic-cartridge manual half-step tracking
- Motor ON/OFF
- Head IN / OUT / STALL / PARK
- HOME anchoring
- Write-protect state
- Density D0-D3
- GUI late connection and reconnect
- RP2350 state caching and STATE resend

The `v0.0.30` tag is historical and immutable.
