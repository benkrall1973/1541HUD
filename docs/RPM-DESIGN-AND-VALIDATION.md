# 1541HUD RPM and SYNC Design / Validation

## Status

T0.0.11 remains the hardware-proven reference implementation for physical-header RPM measurement.

Later development checkpoints added independent UC2 PB7/SYNC monitoring and GUI-side qualification without changing the proven RPM formula:

- T0.0.14: `/CS2`-only UC2 decode, freeing the former CS1 wire
- T0.0.15: UC2 PB7/SYNC -> OneROM GPIO24
- T0.0.16: four-zone SYNC/RPM correlation validation
- T0.0.17: reproduced the ~283 RPM transient while raw SYNC remained normal
- T0.0.18: held last-good RPM through seeks, qualified reacquisition, and discarded mixed post-seek SYNC report windows

The current hardware-test stack uses T0.0.15 firmware with the T0.0.18 GUI.

None of this has yet been promoted to a stable V0.0.32 release.

---

## Primary RPM Method: Physical Header Recurrence

1541 DOS writes decoded header fields to RAM in a distinguishable order.

Actual decoded physical disk header:

    $18 -> $19 -> $1A -> $17 -> $16

DOS pre-search header construction:

    $16 -> $17 -> $18 -> $19 -> $1A

1541HUD recognizes only the first sequence as evidence that a physical GCR header was actually decoded from the rotating disk.

The timestamp is captured when `$0019` is written and the candidate is accepted only after `$001A`, `$0017`, and `$0016` complete the physical-header sequence.

When the same physical track/sector header is observed again, the elapsed time represents one or more complete disk revolutions.

At approximately 300 RPM:

- one revolution is approximately 200 ms
- timestamp resolution is 16 us
- one revolution is approximately 12,500 timer ticks

The estimator infers the nearest integer revolution count from 1 through 4 and calculates RPM from the measured recurrence interval.

Only results between 280.00 and 320.00 RPM are emitted.

Pending RPM history is cleared on physical half-track movement and when the spindle motor turns off.

---

## Why HDRPHY Remains the Primary RPM Source

Physical-header recurrence measures actual full-revolution recurrence rather than estimating revolution time from DOS scheduling or equal sector spacing.

It avoids the formatted-track tail-gap bias seen with NEXTS-based estimation and requires no extra timing assumptions.

Direct PB7/SYNC is now available, but it is deliberately kept independent. It is corroborating physical telemetry, not a requirement for accepting RPM.

This separation proved useful when diagnosing RPM reacquisition artifacts.

---

## Direct UC2 PB7/SYNC Monitoring

The disk-side SYNC signal is available at:

    UC2 pin 17 (PB7 / SYNC)

After T0.0.14 proved that UC2 monitoring works with `/CS2` alone, the former CS1 wire was repurposed:

    UC2 pin 17 (PB7 / SYNC) -> OneROM GPIO24

T0.0.15 counts PB7/SYNC falling edges using passive GPIO input sampling. No extra PIO state machine or DMA channel is used.

The firmware reports one-second raw count windows:

    SYNC T0.0.15 COUNT=<n> LEVEL=<0|1>

`LEVEL` is merely the instantaneous PB7 electrical level at report time. It is retained in diagnostic telemetry but is not useful as a normal HUD status and is hidden by the later GUI.

### Hardware validation

On a normally formatted 1541 disk, each sector normally contributes two SYNC regions, one for the header and one for data.

Expected SYNC events per revolution are therefore approximately:

| Tracks | Density | Sectors | Expected SYNC/rev |
|---:|:---:|---:|---:|
| 1-17 | D3 | 21 | 42 |
| 18-24 | D2 | 19 | 38 |
| 25-30 | D1 | 18 | 36 |
| 31-35 | D0 | 17 | 34 |

T0.0.16 hardware testing produced:

| Track | Density | RPM | SYNC/sec | SYNC/rev estimate |
|---:|:---:|---:|---:|---:|
| 1 | D3 | 300.36 | 210 | 41.95 |
| 18 | D2 | 300.42 | 192 | 38.35 |
| 25 | D1 | 300.42 | 180 | 35.95 |
| 35 | D0 | 300.44 | 170 | 33.95 |

This is a near-exact match to normal 42/38/36/34 zone behavior and strongly validates that GPIO24 is seeing real PB7/SYNC activity.

Motor OFF produced zero SYNC activity in hardware tests.

---

## The ~283 RPM Transient

During earlier real game-loading tests, the HDRPHY estimator occasionally displayed approximately 283 RPM for about one or two seconds around seek/reacquisition.

T0.0.17 reproduced the event while direct PB7/SYNC was active.

A representative observation was approximately:

- displayed RPM: 282.77
- density: D1
- raw SYNC/sec: 180
- head moving / seek state active

A real spindle slowdown from roughly 300.4 RPM to 282.8 RPM would have reduced a normal D1 raw SYNC rate of 180/sec to roughly 169/sec.

Because raw PB7/SYNC remained near 180/sec, the disk was not actually slowing by that amount.

The event is therefore strongly identified as a physical-header recurrence reacquisition artifact rather than a real spindle-speed change.

The RPM formula itself was not changed.

---

## T0.0.18 GUI Qualification

T0.0.18 addresses display/reacquisition behavior without modifying the T0.0.11 RPM firmware algorithm.

### RPM behavior

- Motor OFF blanks RPM and clears qualification state.
- During a seek, the last trustworthy RPM remains visible.
- RPM samples arriving during active/recent movement are not immediately accepted.
- After movement settles, two mutually consistent fresh RPM samples associated with the same decoded header track are required before replacing the held value.
- A large new RPM value is not permanently rejected merely because it differs from the old value. Two agreeing fresh samples may establish a genuinely different spindle speed.

This avoids displaying a one-off reacquisition artifact while still allowing a real sustained speed change to become the new accepted value.

### SYNC/sec behavior

The T0.0.15 firmware produces one-second PB7/SYNC counting windows.

A report that overlaps a long seek can contain activity from multiple tracks/density zones and is not representative of any single settled track. Counts near 380 were observed during long Track-35-to-Track-1 transitions.

The GUI therefore:

- hides SYNC/sec on physical movement
- discards the first complete SYNC report received after the final half-step
- displays the next report immediately

This uses the firmware's report boundary rather than an arbitrary fixed post-seek timer.

### SYNC/rev estimate

The displayed estimate is:

    SYNC/rev = SYNC/sec * 60 / RPM

The arithmetic is effectively instantaneous. Display latency comes from waiting for clean source measurements.

The estimate is shown only when:

- the motor is on
- RPM is fresh rather than held/reacquiring
- a clean SYNC/sec report has been accepted

This intentionally prefers a delayed trustworthy estimate over a fast ratio made from stale/mixed measurements.

---

## Live Sector / FIFO Relationship

The same physical-header detector used for RPM already identifies the decoded sector number.

Later GUI checkpoints therefore added:

- last decoded physical sector
- 10-entry FIFO of recently decoded sectors

These are observations of decoded physical headers, not a claim that the displayed sector is exactly under the head at the instant the GUI refreshes.

The FIFO is cleared on physical track movement and motor OFF.

---

## HOME / Track Reference

Track position is relative until a reliable physical HOME event anchors Track 1.0.

The strong HOME reference remains `$0022 = 1` associated with the drive's physical bump/home behavior.

Changing ROMs can leave the GUI with a previously accumulated position that is internally consistent but no longer trustworthy as an absolute physical track reference.

This was observed while comparing the same game under the original Commodore ROM and JiffyDOS. After physically homing the drive, the JiffyDOS track display returned to the expected physical track range while loading the same disk.

Therefore, after changing drive ROMs or otherwise changing drive state, home the mechanism before treating the displayed track as absolute.

---

## Other RPM Approaches Investigated

### Earlier SYNC counting

Earlier Nano-based monitor experiments showed that disk-side SYNC activity could distinguish density zones and reveal rotational activity. The later direct PB7 connection confirmed this on the OneROM hardware itself.

### Raw read-cycle capture using PIO/DMA

T0.0.0 through T0.0.2 investigated adding another PIO/DMA path for raw disk read activity.

The approach failed to produce a useful read stream and added unnecessary firmware/memory risk. An early experiment also overlapped fixed mailbox RAM before being corrected.

The approach was abandoned.

### Sector 0 detection

T0.0.3 through T0.0.8 investigated `$0019 == 0` and later qualified Sector-0 observations.

This proved useful for recognition research but remained dependent on DOS behavior rather than a strict once-per-revolution physical index.

It was not selected as the primary RPM source.

### NEXTS at $004D

T0.0.9 showed that `$004D`, NEXTS, is a strong software-only rotational timing source.

Naive equal-sector extrapolation produced approximately 304 RPM because normal formatted tracks contain unused tail gap and sectors do not divide the full revolution equally.

NEXTS remains useful as a secondary diagnostic source.

### HDRPHY physical header detection

T0.0.10 established reliable recognition of the actual decoded-header RAM write sequence.

T0.0.11 added the physical recurrence RPM estimator and became the hardware-proven RPM reference implementation.

---

## Fastloader / ROM Compatibility

### Epyx FastLoad

T0.0.10/T0.0.11 testing showed that physical-header detection and RPM remain observable during actual Epyx FastLoad game activity.

Observed examples included:

- Track 20, D2, approximately 300.41 RPM
- Track 29, D1, approximately 300.40 RPM

### JiffyDOS

The current development stack has also been exercised while loading the same game under JiffyDOS.

Loading completed successfully and faster than with the original ROM. After a fresh physical HOME reference was established, displayed track position matched the expected physical range.

### Other DOS variants

Earlier code inspection found compatible NEXTS-related behavior in:

- Commodore DOS
- JiffyDOS 1541 v6.00
- DolphinDOS 2.0
- SpeedDOS

HDRPHY itself does not depend specifically on NEXTS.

---

## T0.0.11 Hardware Validation

| Track | Density | Observed RPM |
|---:|:---:|---:|
| 1.0 | D3 | 300.40 to 300.42 |
| 18.0 | D2 | 300.46 |
| 25.0 | D1 | 300.47 |
| 35.0 | D0 | 300.44 |

The total observed spread was approximately 0.07 RPM.

Real Epyx game-loading additionally produced sane RPM on D2/D1 tracks during active seeking.

---

## Implementation Notes

The T0.0.11 RPM history arrays are deliberately local to the plugin main routine and declared `volatile`.

They must not be moved into unallocated static/global `.bss` storage. Earlier experimentation showed that unallocated persistent plugin state can collide with the fixed 1541HUD mailbox region.

The plugin is freestanding and has no libc. Without `volatile`, GCC optimized explicit initialization/clearing loops into unresolved `memset` calls during development.

Do not casually refactor this proven code while integrating a release candidate.

---

## Current Priority Order

For normal 1541HUD operation:

1. HDRPHY same-track/same-sector recurrence = primary RPM source
2. direct PB7/SYNC = independent physical corroboration / rotational diagnostic
3. NEXTS = secondary software diagnostic source
4. qualified Sector 0 = weaker tertiary diagnostic source

Do not reintroduce the abandoned raw read-capture PIO/DMA experiment without a requirement that cannot be met by the proven mechanisms above.

For the next release, preserve the proven T0.0.11/T0.0.15 firmware behavior and integrate it deliberately into a new release-candidate version rather than rewriting V0.0.30 or relabeling an experimental image.
