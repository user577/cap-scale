"""Runout analysis tab — polar plot, TIR, sync/async error."""

from __future__ import annotations

from collections import deque

import numpy as np
import pyqtgraph as pg
from PySide6.QtCore import QTimer
from PySide6.QtWidgets import (
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from cap_inspector.comm.encoder_link import EncoderLink
from cap_inspector.comm.protocol import MODE_POSITION
from cap_inspector.core.units import counts_to_um


class RunoutTab(QWidget):
    """Polar runout plot with TIR readout — placeholder for spindle integration."""

    def __init__(self, link: EncoderLink, parent=None):
        super().__init__(parent)
        self._link = link
        self._positions: deque[float] = deque(maxlen=10000)
        self._rev_samples = 360  # Samples per revolution
        self._streaming = False

        self._build_ui()
        self._connect_signals()

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._update_plot)
        self._timer.start(200)

    def _build_ui(self):
        layout = QVBoxLayout(self)

        # Controls
        controls = QHBoxLayout()
        self._btn_start = QPushButton("Start Runout")
        self._btn_stop = QPushButton("Stop")
        self._btn_stop.setEnabled(False)
        self._btn_clear = QPushButton("Clear")

        controls.addWidget(self._btn_start)
        controls.addWidget(self._btn_stop)
        controls.addWidget(self._btn_clear)
        controls.addStretch()

        controls.addWidget(QLabel("Samples/Rev:"))
        self._spin_rev = QSpinBox()
        self._spin_rev.setRange(36, 3600)
        self._spin_rev.setValue(360)
        controls.addWidget(self._spin_rev)

        layout.addLayout(controls)

        # Polar plot (using standard plot widget with circular coordinates)
        self._polar_plot = pg.PlotWidget(title="Runout Polar Plot")
        self._polar_plot.setAspectLocked(True)
        self._polar_plot.showGrid(x=True, y=True, alpha=0.2)
        self._polar_curve = self._polar_plot.plot(pen=pg.mkPen('#44aaff', width=2))

        # Reference circle
        theta = np.linspace(0, 2 * np.pi, 100)
        self._polar_plot.plot(
            np.cos(theta), np.sin(theta),
            pen=pg.mkPen('#333333', width=1, style=pg.QtCore.Qt.PenStyle.DashLine),
        )
        layout.addWidget(self._polar_plot)

        # Stats
        stats_group = QGroupBox("Runout Metrics")
        stats_layout = QHBoxLayout()
        self._lbl_tir = QLabel("TIR: -- um")
        self._lbl_sync = QLabel("Sync Error: -- um")
        self._lbl_async = QLabel("Async Error: -- um")
        self._lbl_revs = QLabel("Revolutions: 0")

        for lbl in (self._lbl_tir, self._lbl_sync, self._lbl_async, self._lbl_revs):
            lbl.setStyleSheet("QLabel { font-family: Consolas; font-size: 12px; }")
            stats_layout.addWidget(lbl)
        stats_layout.addStretch()
        stats_group.setLayout(stats_layout)
        layout.addWidget(stats_group)

    def _connect_signals(self):
        self._btn_start.clicked.connect(self._start)
        self._btn_stop.clicked.connect(self._stop)
        self._btn_clear.clicked.connect(self._clear)
        self._spin_rev.valueChanged.connect(self._on_rev_changed)
        self._link.position_received.connect(self._on_position)

    def _start(self):
        if not self._link.is_connected:
            return
        self._positions.clear()
        self._link.start_streaming(MODE_POSITION)
        self._streaming = True
        self._btn_start.setEnabled(False)
        self._btn_stop.setEnabled(True)

    def _stop(self):
        self._link.stop_streaming()
        self._streaming = False
        self._btn_start.setEnabled(True)
        self._btn_stop.setEnabled(False)

    def _clear(self):
        self._positions.clear()

    def _on_rev_changed(self, val: int):
        self._rev_samples = val

    def _on_position(self, pos: int):
        self._positions.append(counts_to_um(pos))

    def _update_plot(self):
        if len(self._positions) < self._rev_samples:
            return

        data = np.array(list(self._positions))
        n_revs = len(data) // self._rev_samples
        self._lbl_revs.setText(f"Revolutions: {n_revs}")

        if n_revs < 1:
            return

        # Use last complete revolution
        last_rev = data[-self._rev_samples:]
        theta = np.linspace(0, 2 * np.pi, len(last_rev), endpoint=False)

        # Normalize for polar plot
        mean_r = np.mean(last_rev)
        deviation = last_rev - mean_r

        # Scale for visibility
        max_dev = max(abs(deviation.max()), abs(deviation.min()), 1.0)
        r_normalized = 1.0 + deviation / max_dev * 0.5

        x = r_normalized * np.cos(theta)
        y = r_normalized * np.sin(theta)
        self._polar_curve.setData(x, y)

        # TIR
        tir = float(last_rev.max() - last_rev.min())
        self._lbl_tir.setText(f"TIR: {tir:.2f} um")

        # Sync error (revolution average)
        if n_revs >= 2:
            reshaped = data[:n_revs * self._rev_samples].reshape(n_revs, self._rev_samples)
            avg_rev = np.mean(reshaped, axis=0)
            sync_err = float(avg_rev.max() - avg_rev.min())
            async_err = float(np.std(reshaped - avg_rev) * 2)
            self._lbl_sync.setText(f"Sync Error: {sync_err:.2f} um")
            self._lbl_async.setText(f"Async Error: {async_err:.2f} um")
