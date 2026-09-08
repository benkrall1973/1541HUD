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
sync_re = re.compile(
    r"SYNC\s+T0\.0\.15\s+COUNT=(\d+)\s+LEVEL=([01])"
)


class HUD1541SyncRevolutionTest(_ProvenDriveHUDCore):
    """T0.0.17 clean validation GUI using proven T0.0.15 telemetry.

    This GUI deliberately does not pretend the one-second SYNC window and an
    HDRPHY RPM sample are synchronous.  It displays the two independent raw
    measurements side by side and derives only an explicitly labelled
    estimate.  The purpose is to catch HDRPHY RPM outliers during real loads
    while preserving the hardware-proven T0.0.15 firmware unchanged.
    """

    FIFO_SIZE = 10

    def __init__(self, root):
        super().__init__(root)
        self.root.title("1541HUD T0.0.17 - Clean SYNC / RPM Validation")
        self.root.geometry("680x860")
        self.root.minsize(680, 860)

        self.rpm_var = tk.StringVar(value="---.--")
        self.sector_var = tk.StringVar(value="--")
        self.sync_var = tk.StringVar(value="0")
        self.sync_level_var = tk.StringVar(value="1")
        self.sync_rev_est_var = tk.StringVar(value="--.--")
        self.status_var = tk.StringVar(value="WAITING")

        self.latest_rpm = None
        self.latest_sync = None
        self.sector_fifo = []
        self.last_fifo_track = None

        self._add_value_row("RPM", self.rpm_var)
        self._add_value_row("SECTOR", self.sector_var)

        sync_frame = ttk.Frame(self.root)
        sync_frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(sync_frame, text="SYNC / SEC", font=("Segoe UI", 12, "bold")).pack(
            side="left", padx=(12, 28)
        )
        ttk.Label(sync_frame, textvariable=self.sync_var, font=("Consolas", 22, "bold")).pack(side="left")
        ttk.Label(sync_frame, text="LEVEL", font=("Segoe UI", 10, "bold")).pack(side="left", padx=(28, 8))
        ttk.Label(sync_frame, textvariable=self.sync_level_var, font=("Consolas", 14, "bold")).pack(side="left")

        estimate_frame = ttk.Frame(self.root)
        estimate_frame.pack(fill="x", padx=18, pady=(0, 6))
        ttk.Label(estimate_frame, text="SYNC / REV EST", font=("Segoe UI", 12, "bold")).pack(
            side="left", padx=(12, 18)
        )
        ttk.Label(estimate_frame, textvariable=self.sync_rev_est_var, font=("Consolas", 22, "bold")).pack(side="left")
        ttk.Label(estimate_frame, text="1 s raw window / latest HDRPHY RPM", font=("Segoe UI", 9)).pack(side="left", padx=(14, 0))

        state_frame = ttk.Frame(self.root)
        state_frame.pack(fill="x", padx=18, pady=(0, 10))
        ttk.Label(state_frame, text="CORRELATION", font=("Segoe UI", 10, "bold")).pack(side="left", padx=(12, 14))
        ttk.Label(state_frame, textvariable=self.status_var, font=("Consolas", 11, "bold")).pack(side="left")

        fifo_frame = ttk.Frame(self.root)
        fifo_frame.pack(fill="x", padx=18, pady=(4, 10))
        ttk.Label(fifo_frame, text="RECENT SECTORS", font=("Segoe UI", 12, "bold")).pack(anchor="w", padx=12, pady=(0, 5))
        fifo_row = ttk.Frame(fifo_frame)
        fifo_row.pack(fill="x", padx=12)
        self.fifo_vars = []
        for _ in range(self.FIFO_SIZE):
            var = tk.StringVar(value="")
            ttk.Label(
                fifo_row,
                textvariable=var,
                width=3,
                anchor="center",
                font=("Consolas", 16, "bold"),
            ).pack(side="left", padx=3)
            self.fifo_vars.append(var)

    def _add_value_row(self, label, variable):
        frame = ttk.Frame(self.root)
        frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(frame, text=label, font=("Segoe UI", 12, "bold")).pack(side="left", padx=(12, 28))
        ttk.Label(frame, textvariable=variable, font=("Consolas", 22, "bold")).pack(side="left")

    def clear_sector_fifo(self):
        self.sector_fifo.clear()
        self.last_fifo_track = None
        self.refresh_sector_fifo()

    def refresh_sector_fifo(self):
        for index, var in enumerate(self.fifo_vars):
            var.set(f"{self.sector_fifo[index]:02d}" if index < len(self.sector_fifo) else "")

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

    def update_estimate(self):
        if not self.motor_on or self.latest_rpm is None or self.latest_sync is None or self.latest_rpm <= 0.0:
            self.sync_rev_est_var.set("--.--")
            self.status_var.set("WAITING")
            return
        value = (self.latest_sync * 60.0) / self.latest_rpm
        self.sync_rev_est_var.set(f"{value:.2f}")
        # Flag large RPM departures without declaring which source is wrong.
        if self.latest_rpm < 295.0 or self.latest_rpm > 305.0:
            self.status_var.set("RPM OUTLIER - CHECK RAW SYNC")
        else:
            self.status_var.set("NORMAL")

    def process_motor(self, state):
        super().process_motor(state)
        if not self.motor_on:
            self.rpm_var.set("---.--")
            self.sector_var.set("--")
            self.latest_rpm = None
            self.latest_sync = None
            self.sync_rev_est_var.set("--.--")
            self.status_var.set("MOTOR OFF")
            self.clear_sector_fifo()

    def process_phase(self, old, new, delta, event_motor):
        super().process_phase(old, new, delta, event_motor)
        if delta in (1, 3):
            self.sector_var.set("--")
            self.latest_rpm = None
            self.latest_sync = None
            self.sync_rev_est_var.set("--.--")
            self.status_var.set("SEEK")
            self.clear_sector_fifo()

    def process_line(self, line):
        m = sync_re.search(line)
        if m:
            self.latest_sync = int(m.group(1))
            self.sync_var.set(m.group(1))
            self.sync_level_var.set(m.group(2))
            self.update_estimate()
            return

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
                self.latest_rpm = float(m.group(3))
                self.rpm_var.set(m.group(3))
                self.update_estimate()
            return

        super().process_line(line)


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541SyncRevolutionTest(root)
    root.mainloop()
