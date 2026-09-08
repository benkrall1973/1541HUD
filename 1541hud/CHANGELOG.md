# 1541HUD Changelog

This changelog tracks 1541HUD/DriveHUD project releases. The repository root `CHANGELOG.md` is retained as upstream OneROM history.

## V0.0.32-RC1 - release candidate, not yet released

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

RC1 must be built and tested on real 1541 hardware before V0.0.32 is released. The tested RC commit, matching BIN/UF2 hashes, matching source copies, GUI, and screenshot should be preserved before promotion.

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
