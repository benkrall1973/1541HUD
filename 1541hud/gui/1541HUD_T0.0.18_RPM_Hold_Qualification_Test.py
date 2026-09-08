import re
import time
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
      * Ignore RPM updates while physical head movement is active and for a
        short settling interval after the most recent half-step.
      * After a seek, require two mutually-consistent fresh RPM samples from
        the same decoded header track before replacing the held value.
      * A large RPM jump while otherwise locked also enters qualification, but
        the new speed is accepted when two fresh samples agree. This rejects a
        one-off acquisition artifact without hiding a genuine spindle change.
      * Raw PB7/SYNC remains independent corroborating telemetry and is never a
        gate for accepting RPM.

    This is intentionally a display/qualification experiment. It does not
    alter PIO, DMA, mailbox layout, physical SYNC counting, or T0.0.15 firmware.
    """

    FIFO_SIZE = 10
    CANDIDATE_AGREE_RPM = 1.50
    LARGE_RPM_JUMP = 5.00
    SEEK_SETTLE_SEC = 0.25
    DISPLAY_FIRMWARE = "T0.0.15"

    def __init__(self, root):
        super().__init__(root)
        self.root.title("1541HUD T0.0.18 - RPM Hold / Qualification Test")

        # The inherited V0.0.30 body uses expand=True. Turn expansion off only
        # in this derived test so the extra diagnostic rows stay compact.
        for child in self.root.pack_slaves():
            info = child.pack_info()
            if info.get("expand") in (1, "1"):
                child.pack_configure(expand=False)

        self.root.geometry("700x760")
        self.root.minsize(700, 760)

        # The inherited core reports its acquisition-core protocol as V0.0.30.
        # This test actually runs the T0.0.15 integrated firmware, so present
        # the build identity that corresponds to the flashed image.
        self.fw_var.set(f"Firmware: {self.DISPLAY_FIRMWARE}")

        self.rpm_var = tk.StringVar(value="---.--")
        self.rpm_state_var = tk.StringVar(value="NO SAMPLE")
        self.sector_var = tk.StringVar(value="--")
        self.sync_var = tk.StringVar(value="0")
        self.sync_rev_est_var = tk.StringVar(value="--.--")

        self.last_good_rpm = None
        self.latest_sync = None
        self.latest_hdr_track = None
        self.reacquiring = True
        self.candidate_rpm = None
        self.candidate_track = None
        self.candidate_count = 0
        self.last_seek_time = None
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

        estimate_frame = ttk.Frame(self.root)
        estimate_frame.pack(fill="x", padx=18, pady=(0, 8))
        ttk.Label(estimate_frame, text="SYNC / REV EST", font=("Segoe UI", 12, "bold")).pack(side="left", padx=(12, 18))
        ttk.Label(estimate_frame, textvariable=self.sync_rev_est_var, font=("Consolas", 22, "bold")).pack(side="left")
        ttk.Label(estimate_frame, text="raw SYNC / fresh RPM", font=("Segoe UI", 9)).pack(side="left", padx=(14, 0))

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

    def reset_candidate(self):
        self.candidate_rpm = None
        self.candidate_track = None
        self.candidate_count = 0

    def begin_reacquire(self, reason):
        self.reacquiring = True
        self.reset_candidate()
        self.sync_rev_est_var.set("--.--")
        if self.last_good_rpm is None:
            self.rpm_state_var.set(f"ACQUIRING ({reason})")
        else:
            self.rpm_state_var.set(f"HOLDING LAST GOOD ({reason})")

    def seek_is_settled(self):
        if self.last_seek_time is None:
            return True
        return (time.monotonic() - self.last_seek_time) >= self.SEEK_SETTLE_SEC

    def update_sync_rev_estimate(self):
        # The one-second SYNC window and RPM sample are independent. During
        # hold/reacquisition the displayed RPM is deliberately stale, so do not
        # manufacture a misleading ratio from old RPM and new SYNC telemetry.
        if (
            not self.motor_on
            or self.reacquiring
            or self.latest_sync is None
            or self.last_good_rpm is None
        ):
            self.sync_rev_est_var.set("--.--")
            return
        self.sync_rev_est_var.set(f"{(self.latest_sync * 60.0) / self.last_good_rpm:.2f}")

    def accept_good_rpm(self, rpm):
        self.last_good_rpm = rpm
        self.rpm_var.set(f"{rpm:.2f}")
        self.rpm_state_var.set("FRESH")
        self.reacquiring = False
        self.reset_candidate()
        self.update_sync_rev_estimate()

    def qualify_rpm(self, track, revolutions, rpm):
        if not self.motor_on:
            return

        # The firmware already clears recurrence history on every real phase
        # change. The GUI additionally refuses queued/early RPM updates until
        # the physical seek has been quiet briefly.
        if not self.seek_is_settled():
            self.begin_reacquire("SEEK")
            return

        # If an RPM record disagrees with the most recently decoded physical
        # header track, treat it as queued/stale acquisition data.
        if self.latest_hdr_track is not None and track != self.latest_hdr_track:
            self.begin_reacquire("TRACK MISMATCH")
            return

        if not self.reacquiring:
            # Normal locked samples update immediately. A large discontinuity
            # must prove itself with a second mutually-consistent sample rather
            # than being permanently vetoed against the old speed.
            if self.last_good_rpm is None or abs(rpm - self.last_good_rpm) <= self.LARGE_RPM_JUMP:
                self.accept_good_rpm(rpm)
                return
            self.begin_reacquire("LARGE CHANGE")

        if self.candidate_rpm is None:
            self.candidate_rpm = rpm
            self.candidate_track = track
            self.candidate_count = 1
            if self.last_good_rpm is None:
                self.rpm_state_var.set("ACQUIRING / CANDIDATE 1")
            else:
                self.rpm_state_var.set("HOLDING LAST GOOD / CANDIDATE 1")
            return

        same_track = track == self.candidate_track
        agrees = abs(rpm - self.candidate_rpm) <= self.CANDIDATE_AGREE_RPM
        if same_track and agrees:
            self.candidate_count += 1
            if self.candidate_count >= 2:
                self.accept_good_rpm(rpm)
            return

        # A different track or disagreeing speed starts a new candidate pair.
        self.candidate_rpm = rpm
        self.candidate_track = track
        self.candidate_count = 1
        if self.last_good_rpm is None:
            self.rpm_state_var.set("ACQUIRING / CANDIDATE RESET")
        else:
            self.rpm_state_var.set("HOLDING LAST GOOD / CANDIDATE RESET")

    def process_motor(self, state):
        super().process_motor(state)
        if not self.motor_on:
            self.rpm_var.set("---.--")
            self.rpm_state_var.set("MOTOR OFF")
            self.last_good_rpm = None
            self.latest_sync = None
            self.latest_hdr_track = None
            self.reacquiring = True
            self.reset_candidate()
            self.last_seek_time = None
            self.sync_rev_est_var.set("--.--")
            self.sector_var.set("--")
            self.clear_sector_fifo()

    def process_phase(self, old, new, delta, event_motor):
        super().process_phase(old, new, delta, event_motor)
        if delta in (1, 3):
            # Keep the last trustworthy RPM visible while the continuously
            # spinning disk seeks, but invalidate measurement qualification.
            self.last_seek_time = time.monotonic()
            self.latest_hdr_track = None
            self.begin_reacquire("SEEK")
            self.sector_var.set("--")
            self.clear_sector_fifo()

    def process_line(self, line):
        m = sync_re.search(line)
        if m:
            self.latest_sync = int(m.group(1))
            self.sync_var.set(m.group(1))
            self.update_sync_rev_estimate()
            return

        m = hdrphy_re.search(line)
        if m:
            if self.motor_on:
                track = int(m.group(1))
                sector = int(m.group(2))
                self.latest_hdr_track = track
                self.sector_var.set(f"{sector:02d}")
                self.push_sector(track, sector)
            return

        m = rpm_re.search(line)
        if m:
            self.qualify_rpm(
                int(m.group(1)),
                int(m.group(2)),
                float(m.group(3)),
            )
            return

        super().process_line(line)

        # The inherited STATE/STATUS parser reports its V0.0.30 acquisition
        # protocol. Keep the visible firmware identity tied to the actual
        # T0.0.15 image under test instead of exposing that internal baseline.
        self.fw_var.set(f"Firmware: {self.DISPLAY_FIRMWARE}")


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541RpmHoldTest(root)
    root.mainloop()
