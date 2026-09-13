# 1541HUD / IEC address change — feasibility and safe design

## Decision

A temporary 1541 IEC address change is feasible while the drive is at rest. The safest implementation is **not** inside the OneROM/1541HUD passive-monitor firmware: that firmware observes 1541 internals and USB telemetry, but it has no electrical connection to ATN, CLK, or DATA and therefore cannot be an IEC bus master.

Use the existing Nano R4 IEC controller as the command sender. The 1541HUD GUI/monitor can supply an idle interlock and display the result; the Nano owns IEC signaling and command completion.

## What changes in a stock 1541

The 1541 DOS accepts the serial **Memory-Write** command (`M-W`). The conventional temporary device-number update writes the desired address twice to RAM locations $0077 and $0078:

```
M-W, address $77, length 2, data <new address>, <new address>
```

The new address takes effect without changing the hardware straps, but it is lost on drive power-off/reset. Hardware address selection is the persistent method on original 1541-family hardware.[^1][^2]

This needs to be treated as a standard IEC transaction to the *current* address. Once the write is accepted, the drive will no longer answer at the old address; verification must therefore query the new address.

## Prior project evidence

Early Nano direct-GPIO attempts sent the intended M-W sequence but failed before a reliable frame acknowledgement, so the drive remained at device 8. Later DriveHUD IEC baseline work did validate temporary/saved address changes and status checks on a physical 1541, with occasional transient `FF` status reads during IEC/DOS settling. The implementation should therefore be based on that later proven IEC framing, not the early V007 framing.

## Recommended architecture

| Component | Responsibility | Must not do |
|---|---|---|
| 1541HUD monitor / GUI | Decide whether the drive is quiet; show progress and result; disable the button when unsafe | Drive IEC lines or claim an address changed before verification |
| Nano R4 IEC controller | Sense/release IEC bus lines; send the M-W transaction; verify at new address; recover safely on timeout | Drive a line high; leave a line asserted after failure |
| 1541 | Receive M-W at old address and begin responding at new address | Be addressed while it is already handling a disk/IEC operation |

A desktop GUI button should send a high-level command to the Nano, e.g. `SET_ADDRESS old new`, rather than attempting IEC itself.

## Idle interlock

The GUI should gray out **Change Address** unless every condition is true:

1. 1541HUD telemetry is connected and fresh.
2. Motor has been off for at least 3 seconds.
3. No recent phase/track/home event has occurred for at least 3 seconds.
4. RPM is stale/zero (not merely one missed sample).
5. The Nano reports IEC idle: ATN, CLK, and DATA released/high for a short stable window.
6. The old address has been positively identified by a DOS-status request.
7. The requested address is different, in the supported UI range 8–11, and is not already occupied by a detected IEC device.

The interlock reduces risk; it is not a guarantee that no other bus master will begin a transaction. The first implementation should therefore be tested with **one 1541 powered and the C64 disconnected**, exactly as in the prior IEC-controller tests.

## Transaction and verification sequence

1. GUI requests a preflight check from the Nano.
2. Nano confirms bus idle and reads DOS status at the old address.
3. Nano sends the existing proven M-W frame to $0077/$0078 with two copies of the new address.
4. Nano releases all IEC lines immediately after the frame.
5. Wait briefly for DOS/IEC settling.
6. Query status at the new address.
7. Report one of: **verified**, **write sent but not verified**, or **not sent / bus failure**.
8. On any timeout, release ATN/CLK/DATA and keep the GUI address state as unknown; never silently assume success.

Do not attempt automatic rollback by broadcasting or probing many addresses. A failed verification should leave recovery to a deliberate manual scan or drive power cycle.

## First implementation scope

Build this outside the 1541HUD passive firmware:

- Preserve T0.0.19 as the monitor/logging checkpoint.
- Start from the later hardware-proven Nano IEC address-manager framing.
- Add only `PRECHECK_ADDRESS_CHANGE`, `SET_ADDRESS`, and `VERIFY_ADDRESS` commands.
- Keep addresses limited to 8–11 initially.
- Use the 1541HUD idle state only as a UI safety gate; have the Nano independently confirm IEC idle.
- Test physical 1541 first, one drive only, C64 disconnected; then test with the C64 attached but idle; finally test 1541 Ultimate separately.

## Recommendation

Proceed with a **Nano-controller address-change test**, not a OneROM firmware test. The first user-facing feature should be a disabled-by-default GUI button that becomes available only when both monitor-idle and IEC-bus-idle checks pass. The feature remains temporary until a persistent mechanism is deliberately designed.

## Sources

[^1]: Commodore, *VIC-1541 Disk Drive User's Manual*, “Changing the Device Number” and DOS command reference. [Project64 mirror](https://project64.c64.org/).
[^2]: Commodore, *1541/1541-II Service Manual*, device-number hardware configuration. [Manual index](https://www.zimmers.net/anonftp/pub/cbm/schematics/drives/new/1541/).
[^3]: OldSilicon, [Commodore DOS Quick Reference](https://oldsilicon.com/), temporary device-number change overview.
