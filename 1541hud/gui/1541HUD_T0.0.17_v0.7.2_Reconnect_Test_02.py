"""Temporary 1541HUD T0.0.17 GUI Test 02: reconnect state recovery.

Requires the sibling T0.0.17 Logging Test GUI and its V0.0.32 dependencies.
No firmware or released GUI files are modified.
"""

import importlib.util
from pathlib import Path
import re
import tkinter as tk


_GUI_PATH = Path(__file__).resolve().parent / "1541HUD_T0.0.17_v0.7.2_Logging_Test.py"
_GUI_SPEC = importlib.util.spec_from_file_location("hud1541_t017_logging", _GUI_PATH)
if _GUI_SPEC is None or _GUI_SPEC.loader is None:
    raise ImportError(f"Unable to load {_GUI_PATH}")
_LOGGING_GUI = importlib.util.module_from_spec(_GUI_SPEC)
_GUI_SPEC.loader.exec_module(_LOGGING_GUI)

# The T0.0.17 firmware wraps the unchanged T0.0.16 monitor. Its USB bridge
# sends STATE T0.0.16 (including TPV/TP2) before live events on reconnect.
# V0.0.32's parser accepts V-prefixed identities only; extend it for this test.
_CORE = _LOGGING_GUI._V0032._CORE
_CORE.state_re = re.compile(r"STATE\s+(T0\.0\.16|V[0-9.]+(?:-RC\d+)?)")
_CORE.status_re = re.compile(r"STATUS\s+(T0\.0\.16|V[0-9.]+(?:-RC\d+)?)")


class HUD1541T0017ReconnectTest02(_LOGGING_GUI.HUD1541T0017LoggingTest):
    """T0.0.17 parser compatibility plus authoritative reconnect snapshot."""

    DISPLAY_FIRMWARE = "T0.0.17 (monitor core T0.0.16)"

    def __init__(self, root):
        super().__init__(root)
        root.title("1541HUD T0.0.17 v0.7.2 Reconnect Test 02")
        self.fw_var.set(f"Firmware: {self.DISPLAY_FIRMWARE}")


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541T0017ReconnectTest02(root)
    root.mainloop()
