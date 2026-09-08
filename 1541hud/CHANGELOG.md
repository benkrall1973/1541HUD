# 1541HUD Changelog

This changelog tracks 1541HUD/DriveHUD project releases. The repository root `CHANGELOG.md` is retained as upstream OneROM history.

## V0.0.32-RC1 - release candidate, hardware-tested

Integrated release-candidate line built from the hardware-proven V0.0.30/V0.0.31 baseline plus the selected T0.x development results.

Included in RC1:

- `/CS2`-only UC2 decode from T0.0.14; the former CS1 monitor wire is no longer required.
- Direct UC2 PB7/SYNC monitoring on GPIO24 from T0.0.15.
- Physical-header RPM measurement from T0.0.11.
- Live last-decoded physical sector display from T0.0.12.
- 10-entry recent-sector FIFO from T0.0.13.
- Four-zone SYNC/RPM validation results from T0.0.16.
- RPM seek/reacquisition diagnosis from T0.0.17.
- Last-good RPM hold, qualified reacquisition, and clean post-seek SYNC report handling from T0.0.18.
- Unified `V0.0.32-RC1` telemetry/build identity for the integrated test image.
- Explicit GUI warning when absolute track position has not yet been HOME-anchored after a ROM change/reset.
- Dual-OneROM and complete passive-monitor wiring documentation.

The exact RC1 firmware and integrated GUI have now been exercised successfully on real Commodore 1541 hardware. Observed together in the RC GUI were HOME anchoring, track/head/motor/write-protect/density state, fresh physical-header RPM, live sector, populated recent-sector FIFO, raw PB7 SYNC/sec, and SYNC/revolution estimation. The RC telemetry parser regression found during first integration was corrected without changing the flashed firmware, and the corrected GUI restored the complete telemetry display.

RC1 remains a release candidate until the final V0.0.32 promotion build and release audit are complete. The tested RC build hashes and source provenance are preserved separately in the repository documentation.

Planned post-V0.0.32 work includes porting the desktop GUI to an LCD touchscreen and separately developing operator controls for IEC device-address changing and write-protect override. These are future control features and are not part of the passive RC1 monitor.

## v0.0.31 - 2026-09-05

Current stable 1541HUD release and project rename baseline.

- Renamed the public project from DriveHUD to 1541HUD.
- Preserved the proven V0.0.30 acquisition and USB mailbox protocol behavior.
- Added canonical 1541HUD source paths, GUI entry point, build script, and documentation.
- Preserved the immutable `v0.0.30` hardware-proven tag.
- Confirmed CI and 1541HUD source sanity checks on the released commit.
- Established `main` as the stable V0.0.31 public branch baseline.

No experimental V0.0.32+ work is part of this release.

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
