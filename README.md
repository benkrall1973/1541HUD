# 1541HUD

**1541HUD** is a passive real-time monitor for the Commodore 1541 disk drive.

It uses a **OneROM Fire-24-E** installed in the 1541 to observe drive activity and send live state to a desktop GUI without taking control of the drive bus.

1541HUD currently monitors:

- Track and half-track position
- Head movement: IN / OUT / STALL / PARK
- HOME / track-1 anchoring
- Spindle motor ON/OFF
- Write-protect state
- Hardware density zone D0-D3
- Drive RPM during physical disk-header activity
- Diagnostic-cartridge half-step movement
- USB disconnect/reconnect and late GUI connection

The monitoring path is designed to remain **passive**. The 1541 continues to execute its normal ROM and disk routines while 1541HUD observes activity in parallel.

---

## Current Status

**Stable release:** 1541HUD V0.0.31

**Latest hardware-proven development checkpoint:** T0.0.11 RPM monitoring

T0.0.11 adds software-only RPM measurement using recurrence of decoded physical disk headers. It requires no additional SYNC wire and has been hardware-tested across all four normal 1541 density zones and during an actual Epyx FastLoad game load.

The T0.0.11 checkpoint is preserved by the tag `rpm-t011-hardware-proven`.

T0.0.11 is a development checkpoint and has not been promoted to V0.0.32.

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

The UB4 monitor observes 6502/VIA activity while UB3 continues to provide the drive ROM.

1541HUD does not replace the 1541 operating system and is not intended to become an IEC controller or active drive emulator.

---

## Proven Monitor Functions

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
| RPM | Proven in T0.0.11 |

RPM measurement is event-driven by real disk-header decoding. Workloads that only move the head or motor, such as some diagnostic routines, may not generate RPM samples until normal sector reads resume.

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
| `docs/RPM-DESIGN-AND-VALIDATION.md` | RPM research, rejected approaches, implementation and hardware validation |
| `OneROM/` | OneROM-derived firmware, plugins, Rust tooling, configuration, hardware support and provenance |
| `OneROM/plugins/user/1541hud-probe/` | Passive 1541 acquisition and decoding plugin |
| `OneROM/plugins/system/usb/` | USB transport and 1541HUD shared mailbox integration |
| `OneROM/firmware/src/piodma/pio.c` | Passive firmware integration |

The separation is organizational, not an attempt to hide the dependency. 1541HUD is built on OneROM and keeps the exact derived build foundation in-tree for reproducibility.

---

## Building After the Repository Refactor

The retained OneROM build tree now lives under `OneROM/`.

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

`Build-1541HUD-Current.ps1` invokes the T0.0.11 canonical builder.

The underlying version-specific builders are retained unchanged and receive `OneROM/` explicitly through their existing `-Repo` parameter. Historical experimental construction scripts are also preserved unchanged so their source remains traceable to the tests that produced them.

---

## Relationship to OneROM

1541HUD is an independent derivative project based on **OneROM v0.7.1**.

**OneROM was created and is maintained by Piers Finlayson.** OneROM provides the Fire-24-E hardware platform, RP2350 firmware architecture, plugin system, firmware build tooling, CLI tooling, board support, and the core source tree used by this project.

1541HUD adds the Commodore 1541-specific passive acquisition, state decoding, mailbox transport, desktop GUI, RPM monitoring, and related testing/documentation.

This repository is **not the upstream OneROM project**, and it is not intended to present upstream OneROM work as original 1541HUD work.

The original OneROM project remains the authoritative source for general OneROM development, hardware, documentation, and support:

- OneROM website: https://onerom.org
- Original OneROM repository: https://github.com/piersfinlayson/one-rom

Additional provenance information is kept in [`OneROM/README.md`](OneROM/README.md).

---

## RPM Monitoring

1541HUD investigated several possible RPM sources, including direct UC2 SYNC monitoring, SYNC counting, raw PIO/DMA disk-read capture, Sector-0 observation, DOS NEXTS timing and physical decoded-header recurrence.

The final T0.0.11 implementation uses **physical decoded-header recurrence**.

The 1541 writes decoded header fields to RAM in this sequence:

```text
$18 -> $19 -> $1A -> $17 -> $16
```

1541HUD recognizes that sequence, timestamps the physical header, and measures recurrence of the same track and sector.

Hardware validation produced approximately:

| Track | Density | RPM |
|---:|:---:|---:|
| 1 | D3 | 300.40-300.42 |
| 18 | D2 | 300.46 |
| 25 | D1 | 300.47 |
| 35 | D0 | 300.44 |

An actual Epyx FastLoad game load also produced valid RPM while the head was actively seeking.

Full design history: [`docs/RPM-DESIGN-AND-VALIDATION.md`](docs/RPM-DESIGN-AND-VALIDATION.md).

---

## Future Development

1541HUD is still being actively explored. Planned or candidate work includes:

- **Live sector activity** — identify and display the sector currently being read when reliable passive observation is possible.
- **Drive/DOS activity state** — expose useful job, command, error, or status information without taking control of the IEC bus.
- **Improved rotational diagnostics** — expand RPM statistics, stability/variation reporting, and investigate secondary RPM sources for workloads that do not decode headers continuously.
- **Fastloader compatibility testing** — continue testing JiffyDOS, DolphinDOS, SpeedDOS, Epyx FastLoad, and other loaders to determine what state remains observable under each.
- **Activity history and logging** — optionally record track movement, motor state, density, RPM, and other events for later analysis.
- **GUI refinement** — improve the desktop display while keeping the monitor simple, readable, and useful on real hardware.
- **Broader 1541 diagnostics** — investigate additional passive signals that can reveal drive behavior without adding unnecessary wiring or disturbing normal operation.
- **Simpler installation and releases** — package proven firmware, matching source, GUI, documentation, and build information so a tested version can be reproduced without reconstructing the development environment.

These are research goals, not promises of completed functionality. New features remain experimental until they are tested on real 1541 hardware and shown not to interfere with normal drive operation.

---

## Versions

### V0.0.30

Original immutable hardware-proven acquisition baseline.

### V0.0.31

Project rename and stable 1541HUD baseline.

### T0.0.11

Hardware-proven development checkpoint adding physical-header RPM monitoring. T0.0.11 remains a test/development version until deliberately promoted to a formal release.

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
