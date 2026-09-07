# 1541HUD RPM Design and Validation

## Status

T0.0.11 is the hardware-proven RPM reference implementation for 1541HUD.

The final method requires no additional SYNC wire, no new PIO state machine, no new DMA channel, and no persistent plugin `.bss` allocation.

It derives rotational speed from physical disk-header decode activity already visible through the passive 1541HUD RAM-write monitor.

## Final Method: Physical Header Recurrence

The 1541 DOS code uses two distinguishable RAM write sequences involving header fields.

Actual decoded physical disk header:

    $18 -> $19 -> $1A -> $17 -> $16

DOS pre-search header construction:

    $16 -> $17 -> $18 -> $19 -> $1A

1541HUD recognizes only the first sequence as evidence that a physical GCR header was actually decoded from the rotating disk.

The timestamp is captured when `$0019` is written and the candidate is accepted only after `$001A`, `$0017`, and `$0016` complete the physical-header sequence.

For each sector number, 1541HUD remembers the previous timestamp on the same physical track. When the same track and sector are observed again, the elapsed time represents one or more complete disk revolutions.

At approximately 300 RPM:

- one revolution is approximately 200 ms
- timestamp resolution is 16 us
- one revolution is approximately 12,500 timer ticks

The estimator infers the nearest integer revolution count from 1 through 4 and calculates RPM from the measured recurrence time.

Only results between 280.00 and 320.00 RPM are accepted.

Pending RPM history is cleared on any physical half-track movement and when the spindle motor turns off. Measurements are never combined across track movement.

The GUI keeps the last valid RPM visible while the motor remains on. When the motor is off the RPM field displays:

    ---.--

## Why This Method Was Chosen

The final HDRPHY recurrence method measures actual physical header recurrence rather than estimating revolution time from logical DOS scheduling or equal sector spacing.

This avoids the formatted-track tail-gap bias seen with NEXTS-based estimation and requires no extra hardware connection.

## Other RPM Approaches Investigated

### Direct SYNC Monitoring

The disk-side SYNC signal is available from UC2 PB7.

A direct SYNC connection could provide continuous rotational information and remains a possible hardware fallback.

It was not selected because it would require another physical wire from the 1541 to OneROM. The final software-only method achieved accurate RPM without modifying the wiring.

### SYNC Counting

Earlier Nano-based monitor experiments counted SYNC activity and demonstrated that disk-side timing information could be used to distinguish density zones and observe rotational activity.

This was useful research but was not adopted as the OneROM RPM mechanism.

### Raw Read-Cycle Capture Using PIO/DMA

T0.0.0 through T0.0.2 investigated adding a second read-capture path to observe disk data more directly.

The proven 1541HUD acquisition path captures 6502 write cycles. The experimental read path attempted to add another PIO state machine and DMA channel.

This approach failed to produce a useful read stream and added unnecessary firmware and memory risk. One early experiment also overlapped fixed mailbox RAM before being corrected.

The approach was abandoned.

### Sector 0 Detection

T0.0.3 through T0.0.8 investigated observing `$0019 == 0`.

This proved that Sector 0-related DOS activity can be detected and timestamped.

However, `$0019 = 0` by itself does not mean physical Sector 0 has just passed under the head. DOS may write the requested sector number while preparing or searching.

Qualified Sector 0 detection improved the signal by requiring a valid current DOS track, but the resulting cadence remained workload-dependent.

Sector 0 detection therefore was not suitable as the primary physical revolution reference.

### NEXTS at $004D

T0.0.9 showed that `$004D`, NEXTS, is a strong software-only rotational timing source.

NEXTS normally advances by two sectors after a decoded header. Timing between NEXTS updates produced highly consistent estimates across all four 1541 density zones.

Naive equal-sector extrapolation produced approximately 304 RPM.

The bias occurs because Commodore-formatted tracks contain unused tail gap. Sectors therefore do not divide the full 360-degree revolution into perfectly equal intervals.

NEXTS remains a useful secondary or diagnostic timing source, but HDRPHY recurrence is preferred because it measures complete physical revolution recurrence directly.

### HDRPHY Physical Header Detection

T0.0.10 introduced detection of the actual decoded-header RAM write sequence.

This successfully distinguished real decoded disk headers from DOS pre-search header construction.

Physical header timing survived normal DOS access and Epyx FastLoad operation.

This became the basis of the T0.0.11 RPM estimator.

## Fastloader Compatibility

### Epyx FastLoad

Epyx FastLoad uploads custom code to 1541 RAM and also calls ROM routines.

T0.0.10 testing showed that both physical-header recognition and NEXTS activity remain observable while Epyx FastLoad is active.

T0.0.11 was then tested during an actual Epyx FastLoad game load.

Observed examples included:

- Track 20, Density D2, RPM 300.41
- Track 29, Density D1, RPM 300.40

The RPM estimator remained valid during seeks and active game loading.

### Other DOS ROMs

Code inspection found compatible NEXTS behavior in:

- Commodore DOS
- JiffyDOS 1541 v6.00
- DolphinDOS 2.0
- SpeedDOS

HDRPHY does not depend specifically on NEXTS, but this inspection supports the broader conclusion that the observed DOS/header RAM structures are common across major 1541 DOS variants.

### MACH 5

MACH 5 was inspected but its exact drive-side implementation was not conclusively established.

It was not used as a final compatibility test because unrelated loading problems made it a poor controlled test case.

## Workloads That May Not Produce RPM

RPM is event-driven by actual physical header decoding.

Some diagnostic workloads exercise the drive mechanically without reading enough physical headers to provide a valid recurrence measurement.

This is expected behavior, not an RPM failure.

Known examples:

- 1541 diagnostic cartridge tests may move the head, operate the motor, change density, or perform bump/home actions without producing usable physical-header recurrence.
- The 1-second track-cycle test is useful for track, density, motor, and head-movement validation but does not necessarily decode sectors continuously enough to produce RPM.

During these workloads the RPM display may remain blank.

Once normal sector reads resume, RPM should reacquire automatically.

A direct SYNC hardware connection would be the fallback if continuous RPM indication were ever required during workloads that perform no physical header decoding.

## T0.0.11 Hardware Validation

T0.0.11 was validated across all four normal 1541 density zones.

| Track | Density | Observed RPM |
|---:|:---:|---:|
| 1.0 | D3 | 300.40 to 300.42 |
| 18.0 | D2 | 300.46 |
| 25.0 | D1 | 300.47 |
| 35.0 | D0 | 300.44 |

The total observed spread was approximately 0.07 RPM.

Real Epyx FastLoad game-loading tests additionally produced:

| Track | Density | Observed RPM |
|---:|:---:|---:|
| 20.0 | D2 | 300.41 |
| 29.0 | D1 | 300.40 |

These results demonstrate:

- correct RPM calculation
- correct operation across all density zones
- correct reacquisition after head movement
- correct operation during fastloader activity
- no requirement for an additional SYNC wire
- no requirement for additional PIO or DMA resources

## Implementation Notes

The RPM history arrays are deliberately local to the plugin main routine.

They must not be moved into unallocated static or global `.bss` storage. Earlier experimentation showed that unallocated persistent plugin state can collide with fixed 1541HUD mailbox RAM.

The history arrays are also intentionally declared `volatile`.

The plugin is freestanding and has no libc. Without `volatile`, GCC may optimize explicit initialization or clearing loops into calls to `memset`, which caused an unresolved linker failure during T0.0.11 development.

## Recommended Priority Order

For future RPM-related work, use this order:

1. HDRPHY same-track/same-sector recurrence
2. NEXTS timing as a secondary diagnostic source
3. qualified Sector 0 only as a weaker software fallback
4. direct SYNC wiring only if truly continuous RPM is required during workloads that decode no physical headers

Do not reintroduce the abandoned raw read-capture PIO/DMA experiment unless there is a new requirement that cannot be met by the proven mechanisms above.
