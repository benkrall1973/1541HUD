# 1541HUD

**1541HUD** is a passive real-time monitor for the Commodore 1541 disk drive.

It uses a **OneROM Fire-24-E** installed in the 1541 to observe drive activity and send live state to a desktop GUI without taking control of the drive bus.

1541HUD currently monitors:

- Track and half-track position
- Head movement: IN / OUT / STALL / PARK
- HOME / track-1 anchoring
- Spindle motor ON/OFF
- Write-protect state
- Hardware density D0-D3
- Physical-header RPM
- Last decoded physical sector
- Recent decoded-sector FIFO
- Raw UC2 PB7/SYNC activity
- Estimated SYNC events per revolution
- Diagnostic-cartridge half-step movement
- USB disconnect/reconnect and late GUI connection

The monitoring path is designed to remain **passive**. The 1541 continues to execute its selected ROM and disk routines while 1541HUD observes activity in parallel.

---

## Current Status

**Stable release:** 1541HUD V0.0.31

**Immutable acquisition baseline:** V0.0.30

**Current hardware-tested development stack:** T0.0.15 firmware with the T0.0.18 GUI.

The development stack combines several separately tested checkpoints:

- **T0.0.11** — physical-header RPM measurement
- **T0.0.12** — live last-decoded physical sector display
- **T0.0.13** — 10-entry recent-sector FIFO
- **T0.0.14** — UC2 decode using `/CS2` alone; the former CS1 wire is no longer required
- **T0.0.15** — direct UC2 PB7/SYNC input on OneROM GPIO24
- **T0.0.16** — four-zone SYNC/RPM correlation validation
- **T0.0.17** — reproduced the ~283 RPM transient and showed raw SYNC remained normal, identifying it as an RPM reacquisition artifact rather than a real spindle slowdown
- **T0.0.18** — holds the last good RPM through seeks, qualifies reacquisition, suppresses mixed post-seek SYNC windows, and restores SYNC/sec and SYNC/rev from clean report boundaries

The T0.0.11 RPM checkpoint is preserved by the tag `rpm-t011-hardware-proven`.

The T0.x line is still development work and has **not** been promoted to V0.0.32.

---

## Hardware Architecture

```text
Commodore 1541
     |
     +-- UB3: normal ROM-serving OneROM
     |
     +-- UB4: passive 1541HUD monitor
                  |
                  v
            RP2350 PIO/DMA
                  |
                  v
          1541HUD state decoder
                  |
                  v
          shared memory mailbox
                  |
                  v
               USB CDC
                  |
                  v
          Python desktop GUI
```

The UB4 monitor observes 6502/VIA activity while UB3 continues to provide the selected drive ROM.

1541HUD does not replace the 1541 operating system and is not intended to become an IEC controller or active drive emulator.

### Current extra signal

The former UC2 CS1 monitor wire has been repurposed:

```text
UC2 pin 17 (PB7 / SYNC) -> OneROM GPIO24
```

UC2 selection for the passive monitor has been hardware-tested using `/CS2` alone.

---

## Proven / Hardware-Tested Monitor Functions

| Function | Status |
|---|---|
| Track position | Proven |
| Half-track position | Proven |
| Diagnostic cartridge half-steps | Proven |
| Head IN / OUT | Proven |
| STALL detection | Proven |
| PARK indication | Proven |
| HOME anchoring | Proven |
| Motor ON/OFF | Proven |
| Write protect | Proven |
| Density D0-D3 | Proven |
| GUI reconnect | Proven |
| Late USB connection | Proven |
| State resend/cache | Proven |
| Physical-header RPM | Proven in T0.0.11 |
| Last decoded physical sector | Proven in T0.0.12 |
| Recent-sector FIFO | Proven in T0.0.13 |
| `/CS2`-only UC2 decode | Proven in T0.0.14 |
| Direct PB7/SYNC input | Proven in T0.0.15 |
| Four-zone SYNC/rev behavior | Proven in T0.0.16 |
| RPM outlier diagnosis using independent SYNC | Proven in T0.0.17 |
| Seek-time RPM hold / qualified reacquisition | Hardware-tested in T0.0.18 |
| Post-seek SYNC report-boundary cleanup | Hardware-tested in T0.0.18 |

RPM measurement is event-driven by real disk-header decoding. Workloads that only move the head or motor may not generate a fresh RPM sample until physical header reads resume.

Track position is relative until a reliable physical HOME event anchors Track 1.0. After changing drive ROMs or otherwise changing drive state, home the mechanism before relying on absolute displayed track position.

See [`docs/RPM-DESIGN-AND-VALIDATION.md`](docs/RPM-DESIGN-AND-VALIDATION.md).

---

## Repository Layout

The repository root is intentionally 1541HUD-focused.

```text
1541HUD/
├── 1541hud/                  1541HUD builders, GUI and development material
├── docs/                     1541HUD documentation
├── OneROM/                   retained OneROM-derived build foundation
├── Makefile                  thin wrapper delegating OneROM build targets
├── README.md
├── RELEASE.md
└── LICENSE.md
```

Important paths:

| Path | Purpose |
|---|---|
| `1541hud/` | 1541HUD build scripts, GUI, release documentation and development artifacts |
| `1541hud/gui/` | Python desktop monitor |
| `1541hud/development/experiments/` | Preserved T0.0.x experimental construction and diagnostic scripts |
| `docs/RPM-DESIGN-AND-VALIDATION.md` | RPM/SYNC research, rejected approaches, implementation and hardware validation |
| `OneROM/` | OneROM-derived firmware, plugins, Rust tooling, configuration, hardware support and provenance |
| `OneROM/plugins/user/1541hud-probe/` | Passive 1541 acquisition and decoding plugin |
| `OneROM/plugins/system/usb/` | USB transport and 1541HUD shared mailbox integration |
| `OneROM/firmware/src/piodma/pio.c` | Passive firmware integration |

The separation is organizational, not an attempt to hide the dependency. 1541HUD is built on OneROM and keeps the exact derived build foundation in-tree for reproducibility.

---

## Building

The retained OneROM build tree lives under `OneROM/`.

The root `Makefile` delegates standard OneROM targets into that directory:

```text
make firmware
make clean
```

For 1541HUD firmware builds, use the project-facing wrappers:

```powershell
.\1541hud\Build-1541HUD-Stable.ps1
.\1541hud\Build-1541HUD-Current.ps1
```

`Build-1541HUD-Stable.ps1` invokes the V0.0.31 canonical builder.

`Build-1541HUD-Current.ps1` invokes the current T0.0.15 SYNC-enabled hardware-test builder. The T0.0.18 work is GUI-side qualification and therefore uses the T0.0.15 firmware image.

Historical version-specific builders and experimental construction scripts remain preserved so source and test binaries stay traceable.

---

## Relationship to OneROM

1541HUD is an independent derivative project based on **OneROM v0.7.1**.

**OneROM was created and is maintained by Piers Finlayson.** OneROM provides the Fire-24-E hardware platform, RP2350 firmware architecture, plugin system, firmware build tooling, CLI tooling, board support, and the core source tree used by this project.

1541HUD adds Commodore 1541-specific passive acquisition, state decoding, mailbox transport, desktop GUI, RPM monitoring, raw SYNC monitoring, and related testing/documentation.

This repository is **not the upstream OneROM project**, and it is not intended to present upstream OneROM work as original 1541HUD work.

The original OneROM project remains the authoritative source for general OneROM development, hardware, documentation, and support:

- OneROM website: https://onerom.org
- Original OneROM repository: https://github.com/piersfinlayson/one-rom

Additional provenance information is kept in [`OneROM/README.md`](OneROM/README.md).

---

## RPM and SYNC Monitoring

The primary RPM source remains **physical decoded-header recurrence** from T0.0.11.

1541HUD recognizes the real decoded-header RAM write order:

```text
$18 -> $19 -> $1A -> $17 -> $16
```

and measures recurrence of the same physical track/sector header.

Direct PB7/SYNC is deliberately independent. It is used as raw rotational telemetry and corroboration, not as a gate for the RPM estimator.

On a normally formatted disk the hardware-tested values are approximately:

| Track | Density | RPM | SYNC/sec | SYNC/rev |
|---:|:---:|---:|---:|---:|
| 1 | D3 | 300.4 | 210 | 42 |
| 18 | D2 | 300.4 | 192 | 38 |
| 25 | D1 | 300.4 | 180 | 36 |
| 35 | D0 | 300.4 | 170 | 34 |

During a previously observed ~283 RPM display transient, raw D1 SYNC stayed near 180/sec. A real slowdown to ~283 RPM would have reduced that raw rate substantially. This independent measurement showed the transient came from HDRPHY reacquisition rather than the spindle actually slowing.

T0.0.18 therefore keeps the last good RPM visible during seeks and accepts a new value only after fresh, mutually consistent post-seek samples. SYNC/sec is also withheld across the mixed one-second window immediately following a seek.

Full design history: [`docs/RPM-DESIGN-AND-VALIDATION.md`](docs/RPM-DESIGN-AND-VALIDATION.md).

---

## ROM / Fastloader Compatibility Testing

The monitor has been exercised with the original Commodore 1541 ROM, Epyx FastLoad activity, and JiffyDOS loading.

A recent same-game comparison under the original ROM and JiffyDOS showed correct monitoring and successful loading under both. JiffyDOS completed the load faster. An initially incorrect displayed track range under JiffyDOS was resolved by physically homing the drive, confirming that the monitor needed a fresh Track-1 reference rather than indicating different disk data placement.

This is why absolute track position should be treated as unanchored until HOME has been observed.

---

## Future Development

Current candidate work includes:

- **Release integration** — consolidate the proven T0.x firmware and GUI behavior into one clean release-candidate version with unified version identity.
- **Drive/DOS activity state** — expose useful job, command, error, or status information without taking control of the IEC bus.
- **Compatibility testing** — continue testing JiffyDOS, DolphinDOS, SpeedDOS, Epyx FastLoad, and other loaders.
- **Activity history and logging** — optionally record track movement, motor state, density, RPM, SYNC, and sector events for later analysis.
- **GUI refinement** — keep the desktop display compact, readable, and explicit about HOME/track-reference validity.
- **Simpler installation and releases** — package proven firmware, matching source, GUI, documentation, and build information so a tested version can be reproduced without reconstructing the development environment.

New features remain experimental until they are tested on real 1541 hardware and shown not to interfere with normal drive operation.

---

## Versions

### V0.0.30

Immutable hardware-proven acquisition baseline. Do not rewrite or repurpose this version.

### V0.0.31

Current stable 1541HUD rename baseline.

### T0.x

Development checkpoints used to isolate and hardware-test new functionality. They are not stable-release version numbers.

The next integrated release should be created as a **new release candidate derived from the proven baseline plus selected T0.x features**, rather than rewriting V0.0.30 or simply relabeling an experimental binary.

---

## Development Model

Active development is performed on `dev-1541hud`.

The stable release line remains on `main`.

Hardware experiments use temporary `T0.0.x` versions and preserve their corresponding source so experimental binaries remain traceable.

Hardware success is not treated as proven until tested on a real Commodore 1541.

---

## Credits

**OneROM** was created by **Piers Finlayson**.

1541HUD depends heavily on his work and on the OneROM hardware, firmware, plugin architecture, and tooling. Upstream material is retained deliberately for provenance and reproducibility.

---

## License

This repository retains the upstream OneROM licensing structure and notices.

Software and firmware are licensed under the MIT License. Applicable hardware design files use the CERN Open Hardware Licence Version 2 - Weakly Reciprocal.

See [`LICENSE.md`](LICENSE.md).
