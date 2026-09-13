# 1541HUD — Future implementation ideas

This is a planning document following the hardware-validated T0.0.19 diagnostic-log checkpoint. It is not a release plan and does not authorize changes to the proven passive PIO/DMA monitor path.

## Recommended next feature

### GUI event history and diagnostic report

Add a GUI panel that records timestamped motor changes, accepted track changes, `HOME ANCHORED`, and write-protect changes. Pair it with a **Copy Diagnostic Report** button that copies firmware identity, connection state, current telemetry, health counters, and recent events to the clipboard.

This makes T0.0.19's bounded diagnostic records useful during ordinary drive testing without modifying firmware capture behavior.

## GUI and diagnostics

- Persist a local GUI event history for motor start/stop, track changes, home anchors, and write-protect changes.
- Export or save that history as plain text or CSV.
- Add a session-health indicator: capture active, RPM fresh/stale, serial connection state, and any ring/queue-overflow warning.
- Show a concise operational state: idle, reading, seeking, homing, stalled, or parked.
- Mark values as fresh or cached after a reconnect.
- Add a compact hardware self-test/report that verifies passive capture, motor transitions, density changes, write protect, and SYNC without commanding the drive.

## Measurement views

- Add an RPM stability display: current, average, minimum, maximum, and deviation during a read.
- Add a disk-zone summary that relates tracks 1–17, 18–24, 25–30, and 31–35 to expected density/SYNC behavior.
- Offer optional native-log filtering: motor only, motor plus accepted track events, or all existing diagnostic records.

## Packaging and integration

- Create a polished release package for the proven T0.0.19 diagnostic build, including BIN/UF2 hashes and a concise user test guide.
- Later, consider a unified operator view with the separate IEC-controller project, while preserving the separation between passive mechanical telemetry and IEC bus functions.

## Guardrails

- Preserve the hardware-proven passive PIO/DMA capture and mailbox ABI.
- Do not treat raw track writes outside the validated 1–35 range as diagnostic-track events.
- Keep native log writes nonblocking and rate bounded.
- Test one focused change at a time on the dedicated UB4 monitor, then record the result before promotion.
