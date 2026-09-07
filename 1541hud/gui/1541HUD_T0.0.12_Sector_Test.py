import re
import tkinter as tk
from tkinter import ttk

from 1541HUD_T0.0.11_RPM_Test import HUD1541RPMTest

hdrphy_re = re.compile(
    r"HDRPHY\s+T0\.0\.11\s+T=(\d+)\s+S=(\d+)\s+US=(\d+)"
)


class HUD1541SectorTest(HUD1541RPMTest):
    """1541HUD T0.0.12 GUI-only live physical-sector display test."""

    def __init__(self, root):
        super().__init__(root)
        self.root.title("1541HUD T0.0.12 - Live Sector Test")
        self.root.geometry("560x580")

        self.sector_var = tk.StringVar(value="--")

        frame = ttk.Frame(self.root)
        frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(frame, text="SECTOR", font=("Segoe UI", 12, "bold")).pack(
            side="left", padx=(12, 28)
        )
        ttk.Label(
            frame, textvariable=self.sector_var, font=("Consolas", 22, "bold")
        ).pack(side="left")

    def process_motor(self, state):
        super().process_motor(state)
        if not self.motor_on:
            self.sector_var.set("--")

    def process_phase(self, old, new, delta, event_motor):
        super().process_phase(old, new, delta, event_motor)
        if delta in (1, 3):
            # A physical half-step invalidates the last sector immediately.
            # A new HDRPHY record will repopulate it after a real header is
            # decoded on the new head position.
            self.sector_var.set("--")

    def process_line(self, line):
        m = hdrphy_re.search(line)
        if m:
            if self.motor_on:
                self.sector_var.set(f"{int(m.group(2)):02d}")
            return
        super().process_line(line)


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541SectorTest(root)
    root.mainloop()
