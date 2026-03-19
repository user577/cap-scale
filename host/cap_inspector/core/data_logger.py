"""CSV data logger for encoder position and diagnostics."""

from __future__ import annotations

import csv
import time
from datetime import datetime
from pathlib import Path


class DataLogger:
    """Writes timestamped position/diagnostics data to CSV files."""

    LOG_DIR = Path.home() / 'cap-scale-logs'

    def __init__(self):
        self._file = None
        self._writer = None
        self._start_time = 0.0
        self._active = False

    @property
    def is_active(self) -> bool:
        return self._active

    @property
    def file_path(self) -> Path | None:
        if self._file and not self._file.closed:
            return Path(self._file.name)
        return None

    def start(self, diagnostics_mode: bool = False) -> Path:
        """Start logging to a new timestamped CSV file."""
        self.stop()

        self.LOG_DIR.mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime('%Y-%m-%d_%H%M%S')
        path = self.LOG_DIR / f'{ts}.csv'

        self._file = open(path, 'w', newline='')
        self._start_time = time.perf_counter()

        if diagnostics_mode:
            fields = ['time_s', 'position', 'sin', 'cos', 'amplitude',
                       'ch0', 'ch1', 'ch2', 'ch3']
        else:
            fields = ['time_s', 'position']

        self._writer = csv.DictWriter(self._file, fieldnames=fields)
        self._writer.writeheader()
        self._active = True
        return path

    def stop(self) -> None:
        """Stop logging and close the file."""
        self._active = False
        if self._file and not self._file.closed:
            self._file.close()
        self._file = None
        self._writer = None

    def log_position(self, position: int) -> None:
        """Log a position-only sample."""
        if not self._active or self._writer is None:
            return
        t = time.perf_counter() - self._start_time
        self._writer.writerow({'time_s': f'{t:.6f}', 'position': position})

    def log_diagnostics(self, data: dict) -> None:
        """Log a full diagnostics sample."""
        if not self._active or self._writer is None:
            return
        t = time.perf_counter() - self._start_time
        row = {
            'time_s': f'{t:.6f}',
            'position': data.get('position', 0),
            'sin': data.get('sin', 0),
            'cos': data.get('cos', 0),
            'amplitude': data.get('amplitude', 0),
            'ch0': data.get('ch0', 0),
            'ch1': data.get('ch1', 0),
            'ch2': data.get('ch2', 0),
            'ch3': data.get('ch3', 0),
        }
        self._writer.writerow(row)
