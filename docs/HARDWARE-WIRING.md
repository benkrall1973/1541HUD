# 1541HUD Hardware and Wiring

## Overview

1541HUD is currently installed in a Commodore 1541 using **two OneROM Fire-24-E boards**.

- **UB3 OneROM** is the normal ROM-serving board. It provides the selected 1541 DOS ROM, such as the original Commodore ROM or JiffyDOS.
- **UB4 OneROM** is dedicated to 1541HUD. It runs the passive monitoring firmware and does not replace or control the drive DOS.

The two-board arrangement keeps ROM service and monitoring separate. The 1541 continues to execute the ROM selected on the UB3 OneROM while the UB4 OneROM observes drive activity and reports it over USB to the 1541HUD desktop GUI.

```text
Commodore 1541

UB3 socket
  |
  +-- OneROM Fire-24-E
      +-- normal ROM-serving role
      +-- original 1541 ROM / JiffyDOS / other selected drive ROM

UB4 socket
  |
  +-- OneROM Fire-24-E
      +-- 1541HUD passive monitor
      +-- RP2350 PIO/DMA acquisition
      +-- shared mailbox
      +-- USB CDC -> desktop GUI
```

## Passive-monitor signal wiring

The current monitor observes the 1541 CPU/VIA bus and one direct disk-side synchronization signal.

| 1541 signal | Source | OneROM/RP2350 signal |
|---|---|---|
| PHI2 | 6502 pin 39 | GPIO8 |
| R/W | 6502 pin 34 | GPIO9 |
| UC2 /CS2 | UC2 6522 pin 23 | GPIO25 |
| UC2 PB7 / SYNC | UC2 6522 pin 17 | GPIO24 |

The PB7/SYNC connection uses the wire that was previously used for UC2 CS1:

```text
UC2 pin 17 (PB7 / SYNC) -> OneROM GPIO24
```

T0.0.14 hardware testing proved that the current UC2 monitor decode works from **/CS2 alone**, so the former CS1 connection is no longer required. GPIO24 was therefore repurposed as the passive physical SYNC input.

## Address and data bus mapping used by 1541HUD

The current passive acquisition wiring uses the following RP2350 GPIO mapping:

### Address bus

| 1541 address line | OneROM/RP2350 GPIO |
|---|---:|
| A0 | 23 |
| A1 | 22 |
| A2 | 21 |
| A3 | 20 |
| A4 | 19 |
| A5 | 18 |
| A6 | 17 |
| A7 | 16 |
| A8 | 15 |
| A9 | 14 |
| A10 | 13 |
| A11 | 11 |
| A12 | 12 |

### Data bus

| 1541 data line | OneROM/RP2350 GPIO |
|---|---:|
| D0 | 7 |
| D1 | 6 |
| D2 | 5 |
| D3 | 0 |
| D4 | 1 |
| D5 | 2 |
| D6 | 3 |
| D7 | 4 |

## Important operating note: HOME reference

1541HUD determines head position by tracking physical stepper phase movement. A physical HOME/bump event provides the strongest absolute Track 1 reference.

After changing the active ROM, resetting the drive, reconnecting in an unusual state, or starting monitoring without a known HOME event, the displayed track can be internally consistent but offset from the real physical track.

Before relying on absolute track position after a ROM change, **home the drive once**. When the monitor observes the Track-1 HOME condition, the GUI reports that Track 1.0 is anchored.

This was confirmed during same-game testing with the original Commodore 1541 ROM and JiffyDOS: the apparent track range initially differed until the drive was homed, after which the displayed physical track range was correct.

## Physical SYNC behavior

The direct UC2 PB7/SYNC input is passive and is used only for observation. It is not used to control the spindle, data separator, or drive bus.

On a normally formatted disk, hardware testing produced approximately:

| Zone | Normal tracks | Density | SYNC/revolution | Approx. SYNC/sec at 300 RPM |
|---|---:|:---:|---:|---:|
| 3 | 1-17 | D3 | 42 | 210 |
| 2 | 18-24 | D2 | 38 | 190 |
| 1 | 25-30 | D1 | 36 | 180 |
| 0 | 31-35 | D0 | 34 | 170 |

These values independently corroborate the physical-header RPM estimator and were useful in proving that the previously observed ~283 RPM transient was a reacquisition artifact rather than a real spindle-speed drop.

## Safety and installation

Power the 1541 **off** before moving or attaching any signal wire. Verify the UC2 pin number and OneROM GPIO destination before powering the drive again.

1541HUD is intended to remain passive. GPIO24 PB7/SYNC is treated as an input-only diagnostic signal, and the current monitoring design does not drive UC2, the 6502 bus, or the disk-side SYNC line.
