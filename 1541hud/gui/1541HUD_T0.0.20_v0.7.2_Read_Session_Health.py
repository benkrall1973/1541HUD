"""1541HUD T0.0.20: GUI-only Read Session & Drive Health test.

Uses the hardware-proven T0.0.19 telemetry stream.  It observes and reports;
it does not alter the passive UB4 monitor, OneROM firmware, IEC bus, or UB3.
"""

import importlib.util
from datetime import datetime
from pathlib import Path
import re
import statistics
import time
import tkinter as tk
from tkinter import ttk


_GUI_PATH = Path(__file__).resolve().parent / "1541HUD_T0.0.17_v0.7.2_Reconnect_Test_02.py"
_GUI_SPEC = importlib.util.spec_from_file_location("hud1541_t017_reconnect", _GUI_PATH)
if _GUI_SPEC is None or _GUI_SPEC.loader is None:
    raise ImportError(f"Unable to load {_GUI_PATH}")
_BASE = importlib.util.module_from_spec(_GUI_SPEC)
_GUI_SPEC.loader.exec_module(_BASE)

_RPM_RE = re.compile(
    r"RPM\s+(?:T0\.0\.11|T0\.0\.16|V[0-9.]+(?:-RC\d+)?)\s+"
    r"T=(\d+)\s+REV=(\d+)\s+RPM=(\d+\.\d{2})"
)
_EVENT_MOTOR_RE = re.compile(r"1541HUD\s+T0\.0\.19\s+EVENT\s+MOTOR=([01])")
_EVENT_TRACK_RE = re.compile(r"1541HUD\s+T0\.0\.19\s+EVENT\s+TRACK=(\d+)")
_EVENT_HOME_RE = re.compile(r"1541HUD\s+T0\.0\.19\s+EVENT\s+HOME=ANCHORED")
_STATUS_RE = re.compile(
    r"STATUS\s+T0\.0\.16\s+CAP=(\d+)\s+PROD=(\d+)\s+CONS=(\d+)"
    r"\s+ROV=(\d+)\s+QOV=(\d+)"
)


class HUD1541T0020ReadSession(_BASE.HUD1541T0017ReconnectTest02):
    """Touch-friendly observation and report layer for T0.0.19 telemetry."""

    DISPLAY_FIRMWARE = "T0.0.19 (monitor core T0.0.16)"

    def __init__(self, root):
        super().__init__(root)
        root.title("1541HUD T0.0.20 v0.7.2 Read Session & Drive Health")
        self.fw_var.set(f"Firmware: {self.DISPLAY_FIRMWARE}")

        self.session_active = False
        self.session_started = None
        self.session_events = []
        self.rpm_samples = []
        self.motor_started = None
        self.motor_seconds = 0.0
        self.overflow_seen = False

        controls = ttk.LabelFrame(root, text="READ SESSION / DRIVE HEALTH")
        controls.pack(fill="x", padx=30, pady=(0, 8))
        row = ttk.Frame(controls)
        row.pack(fill="x", padx=10, pady=8)

        self.session_button = ttk.Button(row, text="Start Session", command=self.toggle_session)
        self.session_button.pack(side="left")
        self.copy_button = ttk.Button(row, text="Stop && Copy Report", command=self.stop_and_copy)
        self.copy_button.pack(side="left", padx=(8, 0))

        self.health_var = tk.StringVar(value="SESSION: not recording")
        ttk.Label(row, textvariable=self.health_var, font=("Segoe UI", 10, "bold")).pack(
            side="left", padx=(16, 0)
        )

        self.event_text = tk.Text(controls, height=6, wrap="word", state="disabled",
                                  font=("Consolas", 9))
        self.event_text.pack(fill="x", padx=10, pady=(0, 8))

    def _now_text(self):
        return datetime.now().strftime("%H:%M:%S")

    def _append_event(self, text):
        line = f"[{self._now_text()}] {text}"
        self.session_events.append(line)
        self.event_text.configure(state="normal")
        self.event_text.insert("end", line + "\n")
        self.event_text.see("end")
        self.event_text.configure(state="disabled")

    def _reset_session(self):
        self.session_events = []
        self.rpm_samples = []
        self.motor_started = time.monotonic() if self.motor_on else None
        self.motor_seconds = 0.0
        self.overflow_seen = False
        self.event_text.configure(state="normal")
        self.event_text.delete("1.0", "end")
        self.event_text.configure(state="disabled")

    def toggle_session(self):
        if self.session_active:
            self.stop_and_copy()
            return
        self._reset_session()
        self.session_active = True
        self.session_started = datetime.now()
        self.session_button.configure(text="Session Running")
        self.health_var.set("SESSION: recording — observation only")
        self._append_event("session started")

    def _finish_motor_time(self):
        if self.motor_started is not None:
            self.motor_seconds += time.monotonic() - self.motor_started
            self.motor_started = None

    def stop_and_copy(self):
        if not self.session_active:
            self.health_var.set("SESSION: no active session to copy")
            return
        self._finish_motor_time()
        self.session_active = False
        self.session_button.configure(text="Start Session")
        report = self.build_report()
        self.root.clipboard_clear()
        self.root.clipboard_append(report)
        self.root.update()
        self._append_event("session stopped — report copied to clipboard")
        self.health_var.set("SESSION: stopped — report copied")

    def build_report(self):
        started = self.session_started.strftime("%Y-%m-%d %H:%M:%S") if self.session_started else "unknown"
        if self.rpm_samples:
            rpm_summary = (
                f"current={self.rpm_samples[-1]:.2f}, avg={statistics.mean(self.rpm_samples):.2f}, "
                f"min={min(self.rpm_samples):.2f}, max={max(self.rpm_samples):.2f}, "
                f"spread={max(self.rpm_samples) - min(self.rpm_samples):.2f}"
            )
        else:
            rpm_summary = "no fresh RPM samples"
        lines = [
            "1541HUD T0.0.20 Read Session Report",
            f"Started: {started}",
            f"Firmware: {self.DISPLAY_FIRMWARE}",
            f"Connection: {'connected' if self.connected else 'disconnected'}",
            f"Motor-on time: {self.motor_seconds:.1f} s",
            f"RPM: {rpm_summary}",
            f"Overflow warning: {'YES' if self.overflow_seen else 'no'}",
            "Events:",
        ]
        lines.extend(self.session_events or ["(none)"])
        return "\n".join(lines)

    def process_line(self, line):
        super().process_line(line)
        self.fw_var.set(f"Firmware: {self.DISPLAY_FIRMWARE}")

        if not self.session_active:
            return

        motor = _EVENT_MOTOR_RE.search(line)
        if motor:
            state = motor.group(1) == "1"
            if state:
                if self.motor_started is None:
                    self.motor_started = time.monotonic()
                self._append_event("motor ON")
            else:
                self._finish_motor_time()
                self._append_event("motor OFF")
            return

        track = _EVENT_TRACK_RE.search(line)
        if track:
            self._append_event(f"accepted track {track.group(1)}")
            return

        if _EVENT_HOME_RE.search(line):
            self._append_event("HOME anchored")
            return

        rpm = _RPM_RE.search(line)
        if rpm:
            value = float(rpm.group(3))
            self.rpm_samples.append(value)
            self.health_var.set(f"SESSION: recording — RPM {value:.2f}")
            return

        status = _STATUS_RE.search(line)
        if status:
            rov, qov = int(status.group(4)), int(status.group(5))
            if rov or qov:
                self.overflow_seen = True
                self._append_event(f"WARNING overflow ROV={rov} QOV={qov}")
                self.health_var.set("SESSION: overflow warning")
            return


if __name__ == "__main__":
    root = tk.Tk()
    app = HUD1541T0020ReadSession(root)
    root.mainloop()
