import re
import tkinter as tk
from tkinter import ttk

from hud_core_v030 import DriveHUD as _ProvenDriveHUDCore

rpm_re = re.compile(r"RPM\s+T0\.0\.11\s+T=(\d+)\s+REV=(\d+)\s+RPM=(\d+\.\d{2})")
hdrphy_re = re.compile(r"HDRPHY\s+T0\.0\.11\s+T=(\d+)\s+S=(\d+)\s+US=(\d+)")
sync_re = re.compile(r"SYNC\s+T0\.0\.15\s+COUNT=(\d+)\s+LEVEL=([01])")


class HUD1541RpmHoldTest(_ProvenDriveHUDCore):
    """T0.0.18 GUI-only RPM hold/reacquisition qualification test.

    Firmware remains the hardware-proven T0.0.15 SYNC input diagnostic.

    Rules:
      * Motor OFF: blank RPM and clear all qualification state.
      * Any real half-step: keep displaying the last good RPM, but mark RPM
        internally stale and begin reacquisition.
      * While motor remains ON, a new RPM sample that differs by more than
        MAX_CONTINUOUS_RPM_JUMP from the held good value is rejected as an
        acquisition outlier.  This specifically tests the observed 282-283 RPM
        post-seek artifact without changing the proven HDRPHY firmware math.
      * Two mutually-consistent fresh candidates are required before replacing
        the held value after a seek.

    This is intentionally a display/qualification experiment.  It does not
    alter PIO, DMA, mailbox layout, physical SYNC counting, or T0.0.15 firmware.
    """

    FIFO_SIZE = 10
    CANDIDATE_AGREE_RPM = 1.50
    MAX_CONTINUOUS_RPM_JUMP = 5.00

    def __init__(self, root):
        super().__init__(root)
        self.root.title("1541HUD T0.0.18 - RPM Hold / Qualification Test")

        # The inherited V0.0.30 body uses expand=True.  Turn expansion off only
        # in this derived test so the extra diagnostic rows stay compact.
        for child in self.root.pack_slaves():
            info = child.pack_info()
            if info.get("expand") in (1, "1"):
                child.pack_configure(expand=False)

        self.root.geometry("700x760")
        self.root.minsize(700, 760)

        self.rpm_var = tk.StringVar(value="---.--")
        self.rpm_state_var = tk.StringVar(value="NO SAMPLE")
        self.sector_var = tk.StringVar(value="--")
        self.sync_var = tk.StringVar(value="0")
        self.sync_level_var = tk.StringVar(value="1")
        self.sync_rev_est_var = tk.StringVar(value="--.--")

        self.last_good_rpm = None
        self.latest_sync = None
        self.reacquiring = True
        self.candidate_rpm = None
        self.candidate_count = 0
        self.sector_fifo = []
        self.last_fifo_track = None

        self._add_value_row("RPM", self.rpm_var)

        state_frame = ttk.Frame(self.root)
        state_frame.pack(fill="x", padx=18, pady=(0, 6))
        ttk.Label(state_frame, text="RPM STATE", font=("Segoe UI", 10, "bold")).pack(side="left", padx=(12, 18))
        ttk.Label(state_frame, textvariable=self.rpm_state_var, font=("Consolas", 11, "bold")).pack(side="left")

        self._add_value_row("SECTOR", self.sector_var)

        sync_frame = ttk.Frame(self.root)
        sync_frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(sync_frame, text="SYNC / SEC", font=("Segoe UI", 12, "bold")).pack(side="left", padx=(12, 28))
        ttk.Label(sync_frame, textvariable=self.sync_var, font=("Consolas", 22, "bold")).pack(side="left")
        ttk.Label(sync_frame, text="LEVEL", font=("Segoe UI", 10, "bold")).pack(side="left", padx=(28, 8))
        ttk.Label(sync_frame, textvariable=self.sync_level_var, font=("Consolas", 14, "bold")).pack(side="left")

        estimate_frame = ttk.Frame(self.root)
        estimate_frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(estimate_frame, text="SYNC / REV EST", font=("Segoe UI", 12, "bold")).pack(side="left", padx=(12, 18))
        ttk.Label(estimate_frame, textvariable=self.sync_rev_est_var, font=("Consolas", 22, "bold")).pack(side="left")
        ttk.Label(estimate_frame, text="raw SYNC / displayed RPM", font=("Segoe UI", 9)).pack(side="left", padx=(14, 0))

        fifo_frame = ttk.LabelFrame(self.root, text="RECENT SECTORS")
        fifo_frame.pack(fill="x", padx=30, pady=(4, 14), ipady=6)
        fifo_row = ttk.Frame(fifo_frame)
        fifo_row.pack(fill="x", padx=10, pady=6)
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

    def begin_reacquire(self, reason):
        self.reacquiring = True
        self.candidate_rpm = None
        self.candidate_count = 0
        if self.last_good_rpm is None:
            self.rpm_state_var.set(f"ACQUIRING ({reason})")
        else:
            self.rpm_state_var.set(f"HOLDING LAST GOOD ({reason})")

    def update_sync_rev_estimate(self):
        if not self.motor_on or self.latest_sync is None or self.last_good_rpm is None:
            self.sync_rev_est_var.set("--.--")
            return
        self.sync_rev_est_var.set(f"{(self.latest_sync * 60.0) / self.last_good_rpm:.2f}")

    def accept_good_rpm(self, rpm):
        self.last_good_rpm = rpm
        self.rpm_var.set(f"{rpm:.2f}")
        self.rpm_state_var.set("FRESH")
        self.reacquiring = False
        self.candidate_rpm = None
        self.candidate_count = 0
        self.update_sync_rev_estimate()

    def qualify_rpm(self, rpm):
        if not self.motor_on:
            return

        if not self.reacquiring:
            # Once locked, normal small changes are accepted immediately.  A
            # large continuous jump is treated as a new reacquisition event so
            # one bad estimator result cannot replace a stable displayed RPM.
            if self.last_good_rpm is not None and abs(rpm - self.last_good_rpm) > self.MAX_CONTINUOUS_RPM_JUMP:
                self.begin_reacquire("OUTLIER")
            else:
                self.accept_good_rpm(rpm)
                return

        if self.last_good_rpm is not None and abs(rpm - self.last_good_rpm) > self.MAX_CONTINUOUS_RPM_JUMP:
            self.rpm_state_var.set("HOLDING LAST GOOD / REJECTED OUTLIER")
            self.candidate_rpm = None
            self.candidate_count = 0
            return

        if self.candidate_rpm is None:
            self.candidate_rpm = rpm
            self.candidate_count = 1
            self.rpm_state_var.set("HOLDING LAST GOOD / CANDIDATE 1") if self.last_good_rpm is not None else self.rpm_state_var.set("ACQUIRING / CANDIDATE 1")
            return

        if abs(rpm - self.candidate_rpm) <= self.CANDIDATE_AGREE_RPM:
            self.candidate_count += 1
            if self.candidate_count >= 2:
                self.accept_good_rpm(rpm)
            return

        # Candidate disagreement restarts qualification from the newest sample.
        self.candidate_rpm = rpm
        self.candidate_count = 1
        self.rpm_state_var.set("HOLDING LAST GOOD / CANDIDATE RESET") if self.last_good_rpm is not None else self.rpm_state_var.set("ACQUIRING / CANDIDATE RESET")

    def process_motor(self, state):
        super().process_motor(state)
        if not self.motor_on:
            self.rpm_var.set("---.--")
            self.rpm_state_var.set("MOTOR OFF")
            self.last_good_rpm = None
            self.latest_sync = None
            self.reacquiring = True
            self.candidate_rpm = None
            self.candidate_count = 0
            self.sync_rev_est_var.set("--.--")
            self.sector_var.set("--")
            self.clear_sector_fifo()

    def process_phase(self, old, new, delta, event_motor):
        super().process_phase(old, new, delta, event_motor)
        if delta in (1, 3):
            # Deliberately keep rpm_var unchanged while the continuously-spinning
            # disk is seeking.  Only measurement validity is reset.
            self.begin_reacquire("SEEK")
            self.sector_var.set("--")
            self.clear_sector_fifo()

    def process_line(self, line):
        m = sync_re.search(line)
        if m:
            self.latest_sync = int(m.group(1))
            self.sync_var.set(m.group(1))
            self.sync_level_var.set(m.group(2))
            self.update_sync_rev_estimate()
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
            self.qualify_rpm(float(m.group(3)))
            return

        super().process_line(line)


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541RpmHoldTest(root)
    root.mainloop()
