import importlib.util
import pathlib
import re
import time
import tkinter as tk

import hud_core_v030 as _CORE


_THIS_DIR = pathlib.Path(__file__).resolve().parent
_T018_PATH = _THIS_DIR / "1541HUD_T0.0.18_RPM_Hold_Qualification_Test.py"
_SPEC = importlib.util.spec_from_file_location("hud_t018", _T018_PATH)
if _SPEC is None or _SPEC.loader is None:
    raise ImportError(f"Could not load T0.0.18 GUI base from {_T018_PATH}")
_T018 = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_T018)

# Preserve the hardware-tested T0.0.18 display/qualification behavior while
# accepting both the historical experimental labels, the tested RC1 labels,
# and the final V0.0.32 telemetry identity.
_VERSION_RPM = r"(?:T0\.0\.16|T0\.0\.11|V0\.0\.32-RC1|V0\.0\.32)"
_VERSION_SYNC = r"(?:T0\.0\.16|T0\.0\.15|V0\.0\.32-RC1|V0\.0\.32)"

_T018.rpm_re = re.compile(
    rf"RPM\s+{_VERSION_RPM}\s+T=(\d+)\s+REV=(\d+)\s+RPM=(\d+\.\d{{2}})"
)
_T018.hdrphy_re = re.compile(
    rf"HDRPHY\s+{_VERSION_RPM}\s+T=(\d+)\s+S=(\d+)\s+US=(\d+)"
)
_T018.sync_re = re.compile(
    rf"SYNC\s+{_VERSION_SYNC}\s+COUNT=(\d+)\s+LEVEL=([01])"
)

_CORE.state_re = re.compile(r"STATE\s+([TV][0-9.]+(?:-RC\d+)?)")
_CORE.status_re = re.compile(r"STATUS\s+([TV][0-9.]+(?:-RC\d+)?)")

HUD1541RpmHoldTest = _T018.HUD1541RpmHoldTest


class HUD1541V0032(HUD1541RpmHoldTest):
    """Final V0.0.32 GUI promoted from the hardware-tested RC1 behavior."""

    DISPLAY_FIRMWARE = "T0.0.16"

    def __init__(self, root):
        super().__init__(root)
        self.root.title("1541HUD T0.0.16")
        self.fw_var.set(f"Firmware: {self.DISPLAY_FIRMWARE}")
        if not self.home_seen:
            self.home_var.set(
                "HOME: reference not confirmed - home drive after ROM change/reset"
            )

    def process_phase(self, old, new, delta, event_motor):
        super(HUD1541RpmHoldTest, self).process_phase(old, new, delta, event_motor)
        if self.motor_on and delta in (1, 3):
            # Keep the last trustworthy RPM visible while the continuously
            # spinning disk seeks, but invalidate measurement qualification.
            self.last_seek_time = time.monotonic()
            self.latest_hdr_track = None
            self.begin_reacquire("SEEK")
            self.sector_var.set("--")
            self.clear_sector_fifo()

            # The current firmware reports one-second PB7/SYNC windows. Any
            # report overlapping this seek may contain multiple tracks or
            # density zones, so discard exactly the first report after the
            # final half-step. The next report is a full clean window and can
            # be displayed without an arbitrary extra timer.
            self.sync_display_valid = False
            self.discard_next_sync_after_seek = True
            self.sync_var.set("--")
            self.sync_rev_est_var.set("--.--")

    def process_line(self, line):
        super().process_line(line)

        if self.home_seen:
            self.home_var.set("HOME: anchored at Track 1.0")
        else:
            self.home_var.set(
                "HOME: reference not confirmed - home drive after ROM change/reset"
            )

        self.fw_var.set(f"Firmware: {self.DISPLAY_FIRMWARE}")


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541V0032(root)
    root.mainloop()
