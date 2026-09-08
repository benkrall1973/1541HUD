import importlib.util
import pathlib
import re
import tkinter as tk

import hud_core_v030 as _CORE


_THIS_DIR = pathlib.Path(__file__).resolve().parent
_T018_PATH = _THIS_DIR / "1541HUD_T0.0.18_RPM_Hold_Qualification_Test.py"
_SPEC = importlib.util.spec_from_file_location("hud_t018", _T018_PATH)
if _SPEC is None or _SPEC.loader is None:
    raise ImportError(f"Could not load T0.0.18 GUI base from {_T018_PATH}")
_T018 = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_T018)

# RC1 deliberately keeps the proven T0.0.18 runtime logic. During integration
# the USB text identity was unified from the experimental T0.0.11/T0.0.15 names
# to V0.0.32-RC1. Accept BOTH forms here so the RC GUI remains compatible with
# the exact hardware-tested T0.0.15 image as well as the relabelled RC1 image.
# This also makes the integration boundary tolerant of any queued/legacy text
# records without changing the acquisition or qualification algorithms.
_VERSION_RPM = r"(?:T0\.0\.11|V0\.0\.32-RC1)"
_VERSION_SYNC = r"(?:T0\.0\.15|V0\.0\.32-RC1)"

_T018.rpm_re = re.compile(
    rf"RPM\s+{_VERSION_RPM}\s+T=(\d+)\s+REV=(\d+)\s+RPM=(\d+\.\d{{2}})"
)
_T018.hdrphy_re = re.compile(
    rf"HDRPHY\s+{_VERSION_RPM}\s+T=(\d+)\s+S=(\d+)\s+US=(\d+)"
)
_T018.sync_re = re.compile(
    rf"SYNC\s+{_VERSION_SYNC}\s+COUNT=(\d+)\s+LEVEL=([01])"
)

# The proven V0.0.30 core originally recognized only dotted version strings
# such as V0.0.30. RC1 adds a suffix, so widen only the parser expressions used
# by that inherited core. The core's track/motor/WP/density behavior itself is
# untouched.
_CORE.state_re = re.compile(r"STATE\s+(V[0-9.]+(?:-RC\d+)?)")
_CORE.status_re = re.compile(r"STATUS\s+(V[0-9.]+(?:-RC\d+)?)")

HUD1541RpmHoldTest = _T018.HUD1541RpmHoldTest


class HUD1541V0032RC1(HUD1541RpmHoldTest):
    """Integrated V0.0.32-RC1 GUI.

    Runtime behavior intentionally inherits the hardware-tested T0.0.18 GUI
    unchanged. This wrapper provides the integrated release-candidate identity,
    accepts both experimental and RC1 telemetry labels, and makes HOME/reference
    validity explicit to the user.
    """

    DISPLAY_FIRMWARE = "V0.0.32-RC1"

    def __init__(self, root):
        super().__init__(root)
        self.root.title("1541HUD V0.0.32-RC1")
        self.fw_var.set(f"Firmware: {self.DISPLAY_FIRMWARE}")
        if not self.home_seen:
            self.home_var.set(
                "HOME: reference not confirmed - home drive after ROM change/reset"
            )

    def process_line(self, line):
        super().process_line(line)

        # Preserve the strong HOME indication from the proven core. Until a
        # real Track-1 anchor has been observed, do not let a DOS-derived
        # startup track value imply that absolute physical position is known.
        if self.home_seen:
            self.home_var.set("HOME: anchored at Track 1.0")
        else:
            self.home_var.set(
                "HOME: reference not confirmed - home drive after ROM change/reset"
            )

        # Keep one visible integrated-build identity even when the parser is
        # accepting legacy experimental labels for compatibility.
        self.fw_var.set(f"Firmware: {self.DISPLAY_FIRMWARE}")


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541V0032RC1(root)
    root.mainloop()
