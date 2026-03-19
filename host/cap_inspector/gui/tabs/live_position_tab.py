"""Live position DRO display tab."""

from __future__ import annotations

import time
from collections import deque

import numpy as np
import pyqtgraph as pg
from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QFont
from PySide6.QtWidgets import (
    QComboBox,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from cap_inspector.comm.encoder_link import EncoderLink
from cap_inspector.comm.protocol import MODE_POSITION
from cap_inspector.core.config import AppConfig
from cap_inspector.core.units import counts_to_mm, counts_to_inch, counts_to_um, format_position


class LivePositionTab(QWidget):
    """Large DRO readout with rolling strip chart and stats."""

    HISTORY_SECONDS = 10
    MAX_POINTS = 2000

    def __init__(self, link: EncoderLink, config: AppConfig, parent=None):
        super().__init__(parent)
        self._link = link
        self._config = config

        self._positions: deque[tuple[float, int]] = deque(maxlen=self.MAX_POINTS)
        self._min_pos = 0
        self._max_pos = 0
        self._sample_count = 0

        self._build_ui()
        self._connect_signals()

        self._update_timer = QTimer(self)
        self._update_timer.timeout.connect(self._update_chart)
        self._update_timer.start(50)  # 20 Hz chart update

    def _build_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 8, 8, 8)

        # Top controls
        top = QHBoxLayout()
        self._btn_start = QPushButton("Start")
        self._btn_stop = QPushButton("Stop")
        self._btn_stop.setEnabled(False)
        self._btn_zero = QPushButton("Zero")
        self._combo_unit = QComboBox()
        self._combo_unit.addItems(['mm', 'um', 'inch'])
        self._combo_unit.setCurrentText(self._config.scale.unit)

        top.addWidget(self._btn_start)
        top.addWidget(self._btn_stop)
        top.addWidget(self._btn_zero)
        top.addStretch()
        top.addWidget(QLabel("Unit:"))
        top.addWidget(self._combo_unit)
        layout.addLayout(top)

        # Large DRO display
        self._lbl_dro = QLabel("0.0000 mm")
        dro_font = QFont("Consolas", 48)
        dro_font.setBold(True)
        self._lbl_dro.setFont(dro_font)
        self._lbl_dro.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._lbl_dro.setStyleSheet(
            "QLabel { background-color: #1a1a2e; color: #00ff88; "
            "border: 2px solid #333; border-radius: 8px; padding: 16px; }"
        )
        layout.addWidget(self._lbl_dro)

        # Strip chart
        self._chart = pg.PlotWidget(title="Position History")
        self._chart.setLabel('left', 'Position', units='mm')
        self._chart.setLabel('bottom', 'Time', units='s')
        self._chart.showGrid(x=True, y=True, alpha=0.3)
        self._curve = self._chart.plot(pen=pg.mkPen('#00ff88', width=2))
        layout.addWidget(self._chart)

        # Stats bar
        stats = QHBoxLayout()
        self._lbl_min = QLabel("Min: --")
        self._lbl_max = QLabel("Max: --")
        self._lbl_p2p = QLabel("P2P: --")
        self._lbl_rate = QLabel("Rate: --")

        for lbl in (self._lbl_min, self._lbl_max, self._lbl_p2p, self._lbl_rate):
            lbl.setStyleSheet("QLabel { font-family: Consolas; font-size: 12px; }")
            stats.addWidget(lbl)

        stats.addStretch()
        layout.addLayout(stats)

    def _connect_signals(self):
        self._btn_start.clicked.connect(self._start)
        self._btn_stop.clicked.connect(self._stop)
        self._btn_zero.clicked.connect(self._zero)
        self._combo_unit.currentTextChanged.connect(self._on_unit_changed)
        self._link.position_received.connect(self._on_position)
        self._link.connection_changed.connect(self._on_connection_changed)

    def _start(self):
        if not self._link.is_connected:
            return
        self._positions.clear()
        self._min_pos = 0
        self._max_pos = 0
        self._sample_count = 0
        self._link.start_streaming(MODE_POSITION)
        self._btn_start.setEnabled(False)
        self._btn_stop.setEnabled(True)

    def _stop(self):
        self._link.stop_streaming()
        self._btn_start.setEnabled(True)
        self._btn_stop.setEnabled(False)

    def _zero(self):
        self._link.send_zero()
        self._positions.clear()
        self._min_pos = 0
        self._max_pos = 0

    def _on_unit_changed(self, unit: str):
        self._config.scale.unit = unit

    def _on_position(self, pos: int):
        now = time.perf_counter()
        self._positions.append((now, pos))
        self._sample_count += 1

        if self._sample_count == 1:
            self._min_pos = pos
            self._max_pos = pos
        else:
            self._min_pos = min(self._min_pos, pos)
            self._max_pos = max(self._max_pos, pos)

        # Update DRO
        unit = self._combo_unit.currentText()
        self._lbl_dro.setText(format_position(
            pos, unit,
            self._config.scale.pitch_um,
            self._config.scale.counts_per_pitch,
        ))

    def _update_chart(self):
        if not self._positions:
            return

        now = time.perf_counter()
        cutoff = now - self.HISTORY_SECONDS

        # Filter to window
        times = []
        values = []
        pitch = self._config.scale.pitch_um
        cpp = self._config.scale.counts_per_pitch

        for t, p in self._positions:
            if t >= cutoff:
                times.append(t - now)
                values.append(counts_to_mm(p, pitch, cpp))

        if times:
            self._curve.setData(times, values)

        # Update stats
        unit = self._combo_unit.currentText()
        self._lbl_min.setText(f"Min: {format_position(self._min_pos, unit, pitch, cpp)}")
        self._lbl_max.setText(f"Max: {format_position(self._max_pos, unit, pitch, cpp)}")
        p2p = self._max_pos - self._min_pos
        self._lbl_p2p.setText(f"P2P: {format_position(p2p, unit, pitch, cpp)}")

        # Rate estimate
        if len(self._positions) >= 2:
            dt = self._positions[-1][0] - self._positions[0][0]
            if dt > 0:
                rate = len(self._positions) / dt
                self._lbl_rate.setText(f"Rate: {rate:.0f} Hz")

    def _on_connection_changed(self, connected: bool):
        if not connected:
            self._btn_start.setEnabled(True)
            self._btn_stop.setEnabled(False)
