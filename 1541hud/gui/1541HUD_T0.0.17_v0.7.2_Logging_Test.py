"""Temporary GUI for the 1541HUD T0.0.17 v0.7.2 logging test.

This keeps the released V0.0.32 GUI behavior while accepting the unchanged
T0.0.16 core telemetry identity emitted by the transport-only T0.0.17 build.
"""

import importlib.util
from pathlib import Path
import re


_GUI_PATH = Path(__file__).resolve().parent / "1541HUD_V0.0.32.py"
_GUI_SPEC = importlib.util.spec_from_file_location("hud1541_v0032", _GUI_PATH)
if _GUI_SPEC is None or _GUI_SPEC.loader is None:
    raise ImportError(f"Unable to load {_GUI_PATH}")
_V0032 = importlib.util.module_from_spec(_GUI_SPEC)
_GUI_SPEC.loader.exec_module(_V0032)


# T0.0.17 deliberately wraps the unchanged T0.0.16 monitor core.  Add that
# identity without changing the released V0.0.32 GUI source.
_V0032._T018.rpm_re = re.compile(
    r"RPM\s+(?:T0\.0\.11|T0\.0\.16|V0\.0\.32-RC1|V0\.0\.32)\s+"
    r"T=(\d+)\s+REV=(\d+)\s+RPM=(\d+\.\d{2})"
)
_V0032._T018.hdrphy_re = re.compile(
    r"HDRPHY\s+(?:T0\.0\.11|T0\.0\.16|V0\.0\.32-RC1|V0\.0\.32)\s+"
    r"T=(\d+)\s+S=(\d+)\s+US=(\d+)"
)
_V0032._T018.sync_re = re.compile(
    r"SYNC\s+(?:T0\.0\.15|T0\.0\.16|V0\.0\.32-RC1|V0\.0\.32)\s+"
    r"COUNT=(\d+)\s+LEVEL=([01])"
)


class HUD1541T0017LoggingTest(_V0032.HUD1541V0032):
    """V0.0.32 GUI behavior with T0.0.16 telemetry compatibility."""

    def __init__(self, root):
        super().__init__(root)
        root.title("1541HUD T0.0.17 v0.7.2 Logging Test")


if __name__ == "__main__":
    root = _V0032._T018.tk.Tk()
    app = HUD1541T0017LoggingTest(root)
    root.mainloop()
