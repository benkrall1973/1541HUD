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


class HUD1541SyncRpmCorrelationTest(_ProvenDriveHUDCore):
    """T0.0.16 GUI-only correlation of raw PB7/SYNC rate and HDRPHY RPM.

    Firmware remains the T0.0.15 SYNC input diagnostic.  The new value is:

        SYNC/rev = (SYNC edges/second * 60) / physical-header RPM

    This does not assume a fixed number of SYNC marks per revolution.  It is
    intended to show whether the independent raw SYNC cadence remains stable
    when the HDRPHY RPM estimator reports an unusual value.
    """

    FIFO_SIZE = 10

    def __init__(self, root):
        super().__init__(root)
        self.root.title("1541HUD T0.0.16 - SYNC / RPM Correlation Test")
        self.root.geometry("650x755")

        self.rpm_var = tk.StringVar(value="---.--")
        self.sector_var = tk.StringVar(value="--")
        self.sync_var = tk.StringVar(value="0")
        self.sync_level_var = tk.StringVar(value="1")
        self.sync_rev_var = tk.StringVar(value="--.--")

        self.latest_rpm = None
        self.latest_sync = None
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

        sync_frame = ttk.Frame(self.root)
        sync_frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(
            sync_frame, text="SYNC / SEC", font=("Segoe UI", 12, "bold")
        ).pack(side="left", padx=(12, 28))
        ttk.Label(
            sync_frame,
            textvariable=self.sync_var,
            font=("Consolas", 22, "bold"),
        ).pack(side="left")
        ttk.Label(sync_frame, text="  LEVEL", font=("Segoe UI", 10, "bold")).pack(
            side="left", padx=(24, 8)
        )
        ttk.Label(
            sync_frame,
            textvariable=self.sync_level_var,
            font=("Consolas", 14, "bold"),
        ).pack(side="left")

        correlation_frame = ttk.Frame(self.root)
        correlation_frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(
            correlation_frame, text="SYNC / REV", font=("Segoe UI", 12, "bold")
        ).pack(side="left", padx=(12, 28))
        ttk.Label(
            correlation_frame,
            textvariable=self.sync_rev_var,
            font=("Consolas", 22, "bold"),
        ).pack(side="left")

        ttk.Label(
            correlation_frame,
            text="  raw SYNC rate / HDRPHY RPM",
            font=("Segoe UI", 9),
        ).pack(side="left", padx=(14, 0))

        fifo_frame = ttk.Frame(self.root)
        fifo_frame.pack(fill="x", padx=18, pady=(4, 10))
        ttk.Label(
            fifo_frame, text="RECENT SECTORS", font=("Segoe UI", 12, "bold")
        ).pack(anchor="w", padx=12, pady=(0, 5))

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

    def clear_sector_fifo(self):
        self.sector_fifo.clear()
        self.last_fifo_track = None
        self.refresh_sector_fifo()

    def refresh_sector_fifo(self):
        for index, var in enumerate(self.fifo_vars):
            var.set(
                f"{self.sector_fifo[index]:02d}"
                if index < len(self.sector_fifo)
                else ""
            )

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

    def clear_correlation(self):
        self.latest_rpm = None
        self.sync_rev_var.set("--.--")

    def update_correlation_from_sync_window(self):
        if (
            not self.motor_on
            or self.latest_rpm is None
            or self.latest_sync is None
            or self.latest_rpm <= 0.0
        ):
            self.sync_rev_var.set("--.--")
            return

        sync_per_rev = (self.latest_sync * 60.0) / self.latest_rpm
        self.sync_rev_var.set(f"{sync_per_rev:.2f}")

    def process_motor(self, state):
        super().process_motor(state)
        if not self.motor_on:
            self.rpm_var.set("---.--")
            self.sector_var.set("--")
            self.clear_sector_fifo()
            self.clear_correlation()

    def process_phase(self, old, new, delta, event_motor):
        super().process_phase(old, new, delta, event_motor)
        if delta in (1, 3):
            self.sector_var.set("--")
            self.clear_sector_fifo()
            # Do not combine a pre-seek RPM sample with a post-seek SYNC rate.
            self.clear_correlation()

    def process_line(self, line):
        m = sync_re.search(line)
        if m:
            self.latest_sync = int(m.group(1))
            self.sync_var.set(m.group(1))
            self.sync_level_var.set(m.group(2))
            # Correlate only when a complete one-second SYNC window arrives.
            self.update_correlation_from_sync_window()
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
                # Wait for the next completed SYNC/SEC window before calculating
                # SYNC/rev so the display is driven by a real raw-SYNC interval.
            return

        super().process_line(line)


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541SyncRpmCorrelationTest(root)
    root.mainloop()
