# 1541HUD — Future implementation ideas

This is a planning document following the hardware-validated T0.0.19 diagnostic-log checkpoint. It is not a release plan and does not authorize changes to the proven passive PIO/DMA monitor path.

## Confirmed architecture

- **UB4 / 1541HUD:** passive drive monitoring, GUI telemetry, diagnostics, and logs.
- **UB3 / OneROM ROM service:** future ROM-based write-protect and IEC-address work.
- These remain separate. 1541HUD must not send IEC commands or alter the proven UB4 monitor path.

## Next implementation: T0.0.20 Read Session & Drive Health

Build the first useful operator feature entirely in the GUI. The firmware remains the validated T0.0.19 event-log build.

### What it does

A **Start Session** button begins a timestamped observation window. During a normal directory read or disk operation, the GUI records:

- motor start/stop and elapsed motor-on time;
- accepted track changes and HOME anchors;
- write-protect and density changes;
- fresh/stale RPM, with current, average, minimum, maximum, and spread;
- valid sector/SYNC activity and recent sectors;
- connection/reconnection events;
- any capture/ring/queue overflow status exposed by existing telemetry.

A **Stop & Copy Report** button creates a short text report for clipboard/export. It reports what actually occurred; it never commands the drive.

### Safety and UI behavior

- **Start Session** is always safe: it only observes.
- A session clearly shows **Idle**, **Reading**, **Seeking**, **Homing**, **Stalled**, or **Parked** as an inferred display state, never as an unverified firmware command state.
- After reconnect, the GUI labels retained values **cached** until fresh telemetry arrives.
- The screen stays touch-friendly so the same design can later run on the planned approximately 7-inch drive-top LCD.
- The normal Windows GUI remains the full-detail development view.

### First acceptance test

1. Start a session with the drive idle.
2. Read a directory from a known-good disk.
3. Stop the session after the motor stops.
4. Verify the report includes motor idle → active → idle, accepted track activity, plausible RPM around 300, sector/SYNC activity, and no overflow warning.
5. Disconnect and reconnect once; verify the report marks the reconnection and returns to fresh telemetry.
6. Repeat with the existing C64 track-cycle program to verify 18 → 25 → 35 → 1 and one HOME anchor.

## T0.0.20 hardware result — 2026-09-13

**PASS — GUI-only Read Session & Drive Health.** With the hardware-proven T0.0.19 EventLog firmware unchanged, the new single-window GUI recorded and rendered a normal track-cycle session. The report showed motor-on time **39.3 s**, RPM **300.41–300.60** (average **300.50**, spread **0.19**), accepted tracks **18 → 25 → 35 → 1**, one **HOME anchored**, and **no overflow warning**.

The report now remains visible in the right-hand GUI panel when stopped and is also copied to the clipboard. No firmware, passive PIO/DMA path, UB3 ROM service, IEC, or write-protect behavior was changed.

## Later GUI and diagnostics

- Persist local event history and export it as plain text or CSV.
- Add a compact hardware self-test/report that verifies passive capture, motor transitions, density changes, write protect, and SYNC without commanding the drive.
- Add a disk-zone summary that relates tracks 1–17, 18–24, 25–30, and 31–35 to expected density/SYNC behavior.
- Offer optional native-log filtering: motor only, motor plus accepted track events, or all existing diagnostic records.
- Add a drive-profile view for notes, expected RPM, observed density boundaries, and repeated trouble tracks.
- Add bounded raw diagnostic capture (“next 10 seconds”) for difficult faults, saved as text/CSV rather than flooding the live log.

## Packaging and integration

- Create a polished release package for the proven T0.0.19 diagnostic build, including BIN/UF2 hashes and a concise user test guide.
- Later, consider a unified operator view with the separate UB3/OneROM control device, while preserving the separation between passive mechanical telemetry and ROM/IEC functions.

## Guardrails

- Preserve the hardware-proven passive PIO/DMA capture and mailbox ABI.
- Do not treat raw track writes outside the validated 1–35 range as diagnostic-track events.
- Keep native log writes nonblocking and rate bounded.
- Test one focused change at a time on the dedicated UB4 monitor, then record the result before promotion.
