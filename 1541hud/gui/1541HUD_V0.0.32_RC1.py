import importlib.util
import pathlib
import tkinter as tk


_THIS_DIR = pathlib.Path(__file__).resolve().parent
_T018_PATH = _THIS_DIR / "1541HUD_T0.0.18_RPM_Hold_Qualification_Test.py"
_SPEC = importlib.util.spec_from_file_location("hud_t018", _T018_PATH)
if _SPEC is None or _SPEC.loader is None:
    raise ImportError(f"Could not load T0.0.18 GUI base from {_T018_PATH}")
_T018 = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_T018)
HUD1541RpmHoldTest = _T018.HUD1541RpmHoldTest


class HUD1541V0032RC1(HUD1541RpmHoldTest):
    """Integrated V0.0.32-RC1 GUI.

    Runtime behavior intentionally inherits the hardware-tested T0.0.18 GUI
    unchanged. This wrapper only gives the integrated release candidate a
    unified identity and makes HOME/reference validity explicit to the user.
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

        # T0.0.18 intentionally displayed the T0.0.15 experimental firmware
        # identity. RC1 uses a matching integrated firmware build, so present
        # the release-candidate identity instead.
        self.fw_var.set(f"Firmware: {self.DISPLAY_FIRMWARE}")


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541V0032RC1(root)
    root.mainloop()
