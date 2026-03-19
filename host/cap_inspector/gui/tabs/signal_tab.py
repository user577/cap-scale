"""Signal quality tab — Lissajous plot, channel amplitudes, error metrics."""

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
    QVBoxLayout,
    QWidget,
)

from cap_inspector.comm.encoder_link import EncoderLink
from cap_inspector.comm.protocol import MODE_DIAGNOSTICS


class SignalTab(QWidget):
    """Lissajous plot (sin vs cos), channel amplitudes, and error metrics."""

    MAX_LISSAJOUS = 500

    def __init__(self, link: EncoderLink, parent=None):
        super().__init__(parent)
        self._link = link
        self._sin_buf: deque[float] = deque(maxlen=self.MAX_LISSAJOUS)
        self._cos_buf: deque[float] = deque(maxlen=self.MAX_LISSAJOUS)
        self._amplitudes: list[float] = [0.0] * 4
        self._streaming = False

        self._build_ui()
        self._connect_signals()

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._update_plots)
        self._timer.start(100)

    def _build_ui(self):
        layout = QHBoxLayout(self)

        # Left: Lissajous plot
        left = QVBoxLayout()
        self._btn_start = QPushButton("Start Signal Monitor")
        self._btn_stop = QPushButton("Stop")
        self._btn_stop.setEnabled(False)

        btn_row = QHBoxLayout()
        btn_row.addWidget(self._btn_start)
        btn_row.addWidget(self._btn_stop)
        btn_row.addStretch()
        left.addLayout(btn_row)

        self._lissajous = pg.PlotWidget(title="Lissajous (Sin vs Cos)")
        self._lissajous.setAspectLocked(True)
        self._lissajous.showGrid(x=True, y=True, alpha=0.3)
        self._lissajous.setLabel('bottom', 'Sin')
        self._lissajous.setLabel('left', 'Cos')
        self._liss_curve = self._lissajous.plot(
            pen=None, symbol='o', symbolSize=3,
            symbolBrush=pg.mkBrush('#00aaff'),
        )
        # Reference circle
        theta = np.linspace(0, 2 * np.pi, 100)
        self._lissajous.plot(
            np.cos(theta) * 1000, np.sin(theta) * 1000,
            pen=pg.mkPen('#555555', width=1, style=pg.QtCore.Qt.PenStyle.DashLine),
        )
        left.addWidget(self._lissajous)
        layout.addLayout(left, 2)

        # Right: metrics
        right = QVBoxLayout()

        # Amplitude bars
        amp_group = QGroupBox("Channel Amplitudes")
        amp_layout = QVBoxLayout()
        self._amp_bars = pg.PlotWidget()
        self._amp_bars.setMaximumHeight(200)
        self._amp_bars.setLabel('bottom', 'Channel')
        self._amp_bars.setLabel('left', 'Amplitude')
        self._bar_item = pg.BarGraphItem(
            x=[0, 1, 2, 3], height=[0, 0, 0, 0], width=0.6,
            brush=pg.mkBrush('#00aaff'),
        )
        self._amp_bars.addItem(self._bar_item)
        amp_layout.addWidget(self._amp_bars)
        amp_group.setLayout(amp_layout)
        right.addWidget(amp_group)

        # Error metrics
        metrics_group = QGroupBox("Signal Quality Metrics")
        metrics_layout = QVBoxLayout()
        self._lbl_offset = QLabel("DC Offset: --")
        self._lbl_imbalance = QLabel("Gain Imbalance: --")
        self._lbl_phase = QLabel("Phase Error: --")
        self._lbl_amplitude = QLabel("Amplitude: --")
        self._lbl_snr = QLabel("SNR: --")

        for lbl in (self._lbl_offset, self._lbl_imbalance, self._lbl_phase,
                     self._lbl_amplitude, self._lbl_snr):
            lbl.setStyleSheet("QLabel { font-family: Consolas; font-size: 11px; }")
            metrics_layout.addWidget(lbl)

        metrics_group.setLayout(metrics_layout)
        right.addWidget(metrics_group)
        right.addStretch()

        layout.addLayout(right, 1)

    def _connect_signals(self):
        self._btn_start.clicked.connect(self._start)
        self._btn_stop.clicked.connect(self._stop)
        self._link.diagnostics_received.connect(self._on_diagnostics)

    def _start(self):
        if not self._link.is_connected:
            return
        self._sin_buf.clear()
        self._cos_buf.clear()
        self._link.start_streaming(MODE_DIAGNOSTICS)
        self._streaming = True
        self._btn_start.setEnabled(False)
        self._btn_stop.setEnabled(True)

    def _stop(self):
        self._link.stop_streaming()
        self._streaming = False
        self._btn_start.setEnabled(True)
        self._btn_stop.setEnabled(False)

    def _on_diagnostics(self, data: dict):
        self._sin_buf.append(data['sin'])
        self._cos_buf.append(data['cos'])
        self._amplitudes = [
            abs(data.get('ch0', 0)),
            abs(data.get('ch1', 0)),
            abs(data.get('ch2', 0)),
            abs(data.get('ch3', 0)),
        ]

    def _update_plots(self):
        if not self._sin_buf:
            return

        # Lissajous
        sin_arr = np.array(self._sin_buf)
        cos_arr = np.array(self._cos_buf)
        self._liss_curve.setData(sin_arr, cos_arr)

        # Amplitude bars
        self._bar_item.setOpts(height=self._amplitudes)

        # Metrics
        if len(sin_arr) > 10:
            sin_mean = float(np.mean(sin_arr))
            cos_mean = float(np.mean(cos_arr))
            sin_amp = float(np.std(sin_arr) * np.sqrt(2))
            cos_amp = float(np.std(cos_arr) * np.sqrt(2))

            self._lbl_offset.setText(f"DC Offset: sin={sin_mean:.0f}  cos={cos_mean:.0f}")

            if cos_amp > 0:
                imbalance = abs(sin_amp - cos_amp) / max(sin_amp, cos_amp) * 100
                self._lbl_imbalance.setText(f"Gain Imbalance: {imbalance:.1f}%")

            avg_amp = (sin_amp + cos_amp) / 2
            self._lbl_amplitude.setText(f"Amplitude: {avg_amp:.0f}")

            # Phase error from cross-correlation
            sin_c = sin_arr - sin_mean
            cos_c = cos_arr - cos_mean
            if sin_amp > 0 and cos_amp > 0:
                cross = float(np.mean(sin_c * cos_c)) / (sin_amp * cos_amp / 2)
                phase_deg = float(np.degrees(np.arcsin(np.clip(cross, -1, 1))))
                self._lbl_phase.setText(f"Phase Error: {phase_deg:.1f} deg")
