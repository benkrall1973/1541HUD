import re
import tkinter as tk
from tkinter import ttk

from hud_core_v030 import DriveHUD as _ProvenDriveHUDCore

rpm_re = re.compile(
    r"RPM\s+T0\.0\.11\s+T=(\d+)\s+REV=(\d+)\s+RPM=(\d+\.\d{2})"
)


class HUD1541RPMTest(_ProvenDriveHUDCore):
    """1541HUD T0.0.11 final RPM validation GUI."""

    def __init__(self, root):
        super().__init__(root)
        self.root.title("1541HUD T0.0.11 - Final RPM Test")
        self.root.geometry("560x520")

        self.rpm_var = tk.StringVar(value="---.--")

        frame = ttk.Frame(self.root)
        frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(frame, text="RPM", font=("Segoe UI", 12, "bold")).pack(
            side="left", padx=(12, 28)
        )
        ttk.Label(
            frame, textvariable=self.rpm_var, font=("Consolas", 22, "bold")
        ).pack(side="left")

    def process_motor(self, state):
        super().process_motor(state)
        if not self.motor_on:
            self.rpm_var.set("---.--")

    def process_line(self, line):
        m = rpm_re.search(line)
        if m:
            if self.motor_on:
                self.rpm_var.set(m.group(3))
            return
        super().process_line(line)


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541RPMTest(root)
    root.mainloop()
