import re
import tkinter as tk
from tkinter import ttk

from hud_core_v030 import DriveHUD as _ProvenDriveHUDCore

rpm_re = re.compile(
    r"RPM\s+T0\.0\.11\s+T=(\d+)\s+REV=(\d+)\s+RPM=(\d+\.\d{2})"
)
hdrphy_re = re.compile(
    r"HDRPHY\s+T0\.0\.11\s+T=(\d+)\s+S=(\d+)\s+US=(\d+)"
)


class HUD1541SectorFIFOTest(_ProvenDriveHUDCore):
    """1541HUD T0.0.13 GUI-only live physical-sector FIFO display test."""

    FIFO_SIZE = 10

    def __init__(self, root):
        super().__init__(root)
        self.root.title("1541HUD T0.0.13 - Live Sector FIFO Test")
        self.root.geometry("620x650")

        self.rpm_var = tk.StringVar(value="---.--")
        self.sector_var = tk.StringVar(value="--")
        self.sector_fifo = []
        self.last_fifo_track = None

        rpm_frame = ttk.Frame(self.root)
        rpm_frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(rpm_frame, text="RPM", font=("Segoe UI", 12, "bold")).pack(
            side="left", padx=(12, 28)
        )
        ttk.Label(
            rpm_frame, textvariable=self.rpm_var, font=("Consolas", 22, "bold")
        ).pack(side="left")

        sector_frame = ttk.Frame(self.root)
        sector_frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(
            sector_frame, text="SECTOR", font=("Segoe UI", 12, "bold")
        ).pack(side="left", padx=(12, 28))
        ttk.Label(
            sector_frame,
            textvariable=self.sector_var,
            font=("Consolas", 22, "bold"),
        ).pack(side="left")

        fifo_frame = ttk.Frame(self.root)
        fifo_frame.pack(fill="x", padx=18, pady=(4, 10))
        ttk.Label(
            fifo_frame, text="RECENT SECTORS", font=("Segoe UI", 12, "bold")
        ).pack(anchor="w", padx=12, pady=(0, 5))

        fifo_row = ttk.Frame(fifo_frame)
        fifo_row.pack(fill="x", padx=12)

        self.fifo_vars = []
        self.fifo_labels = []
        for _ in range(self.FIFO_SIZE):
            var = tk.StringVar(value="")
            label = ttk.Label(
                fifo_row,
                textvariable=var,
                width=3,
                anchor="center",
                font=("Consolas", 16, "bold"),
            )
            label.pack(side="left", padx=3)
            self.fifo_vars.append(var)
            self.fifo_labels.append(label)

    def clear_sector_fifo(self):
        self.sector_fifo.clear()
        self.last_fifo_track = None
        self.refresh_sector_fifo()

    def refresh_sector_fifo(self):
        for index, var in enumerate(self.fifo_vars):
            if index < len(self.sector_fifo):
                var.set(f"{self.sector_fifo[index]:02d}")
            else:
                var.set("")

    def push_sector(self, track, sector):
        if self.last_fifo_track is None:
            self.last_fifo_track = track
        elif track != self.last_fifo_track:
            self.sector_fifo.clear()
            self.last_fifo_track = track

        self.sector_fifo.append(sector)
        if len(self.sector_fifo) > self.FIFO_SIZE:
            self.sector_fifo.pop(0)
        self.refresh_sector_fifo()

    def process_motor(self, state):
        super().process_motor(state)
        if not self.motor_on:
            self.rpm_var.set("---.--")
            self.sector_var.set("--")
            self.clear_sector_fifo()

    def process_phase(self, old, new, delta, event_motor):
        super().process_phase(old, new, delta, event_motor)
        if delta in (1, 3):
            # A physical half-step invalidates the last decoded sector and
            # starts a fresh FIFO for the new head position.
            self.sector_var.set("--")
            self.clear_sector_fifo()

    def process_line(self, line):
        m = hdrphy_re.search(line)
        if m:
            if self.motor_on:
                track = int(m.group(1))
                sector = int(m.group(2))
                self.sector_var.set(f"{sector:02d}")
                self.push_sector(track, sector)
            return

        m = rpm_re.search(line)
        if m:
            if self.motor_on:
                self.rpm_var.set(m.group(3))
            return

        super().process_line(line)


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541SectorFIFOTest(root)
    root.mainloop()
