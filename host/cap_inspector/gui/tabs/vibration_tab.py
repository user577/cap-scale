"""Vibration/FFT analysis tab."""

from __future__ import annotations

from collections import deque

import numpy as np
import pyqtgraph as pg
from PySide6.QtCore import QTimer
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
from cap_inspector.core.units import counts_to_um


class VibrationTab(QWidget):
    """FFT magnitude plot, peak frequency/amplitude, RMS displacement."""

    def __init__(self, link: EncoderLink, config: AppConfig, parent=None):
        super().__init__(parent)
        self._link = link
        self._config = config
        self._streaming = False

        self._buf: deque[float] = deque(maxlen=8192)
        self._sample_rate = 1000.0  # Estimated, updated from data

        self._build_ui()
        self._connect_signals()

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._update_fft)
        self._timer.start(200)

    def _build_ui(self):
        layout = QVBoxLayout(self)

        # Controls
        controls = QHBoxLayout()
        self._btn_start = QPushButton("Start FFT")
        self._btn_stop = QPushButton("Stop")
        self._btn_stop.setEnabled(False)

        controls.addWidget(self._btn_start)
        controls.addWidget(self._btn_stop)
        controls.addStretch()

        controls.addWidget(QLabel("Window:"))
        self._combo_window = QComboBox()
        self._combo_window.addItems(['256', '512', '1024', '2048', '4096'])
        self._combo_window.setCurrentText('1024')
        controls.addWidget(self._combo_window)

        layout.addLayout(controls)

        # FFT plot
        self._fft_plot = pg.PlotWidget(title="Vibration FFT")
        self._fft_plot.setLabel('bottom', 'Frequency', units='Hz')
        self._fft_plot.setLabel('left', 'Amplitude', units='um')
        self._fft_plot.showGrid(x=True, y=True, alpha=0.3)
        self._fft_plot.setLogMode(x=False, y=False)
        self._fft_curve = self._fft_plot.plot(pen=pg.mkPen('#ff6644', width=2))
        layout.addWidget(self._fft_plot)

        # Stats
        stats = QHBoxLayout()
        self._lbl_peak_freq = QLabel("Peak: -- Hz")
        self._lbl_peak_amp = QLabel("Peak Amp: -- um")
        self._lbl_rms = QLabel("RMS: -- um")
        self._lbl_samples = QLabel("Samples: 0")

        for lbl in (self._lbl_peak_freq, self._lbl_peak_amp, self._lbl_rms, self._lbl_samples):
            lbl.setStyleSheet("QLabel { font-family: Consolas; font-size: 12px; }")
            stats.addWidget(lbl)
        stats.addStretch()
        layout.addLayout(stats)

    def _connect_signals(self):
        self._btn_start.clicked.connect(self._start)
        self._btn_stop.clicked.connect(self._stop)
        self._link.position_received.connect(self._on_position)

    def _start(self):
        if not self._link.is_connected:
            return
        self._buf.clear()
        self._link.start_streaming(MODE_POSITION)
        self._streaming = True
        self._btn_start.setEnabled(False)
        self._btn_stop.setEnabled(True)

    def _stop(self):
        self._link.stop_streaming()
        self._streaming = False
        self._btn_start.setEnabled(True)
        self._btn_stop.setEnabled(False)

    def _on_position(self, pos: int):
        um = counts_to_um(pos, self._config.scale.pitch_um,
                          self._config.scale.counts_per_pitch)
        self._buf.append(um)

    def _update_fft(self):
        window_size = int(self._combo_window.currentText())
        self._lbl_samples.setText(f"Samples: {len(self._buf)}")

        if len(self._buf) < window_size:
            return

        # Use most recent samples
        data = np.array(list(self._buf))[-window_size:]
        data = data - np.mean(data)  # Remove DC

        # Hanning window
        windowed = data * np.hanning(window_size)

        # FFT
        fft_vals = np.fft.rfft(windowed)
        magnitude = np.abs(fft_vals) * 2.0 / window_size

        # Frequency axis (assume ~1 kHz sample rate — will be updated from actual timing)
        freqs = np.fft.rfftfreq(window_size, d=1.0 / self._sample_rate)

        # Skip DC bin
        freqs = freqs[1:]
        magnitude = magnitude[1:]

        self._fft_curve.setData(freqs, magnitude)

        # Peak
        if len(magnitude) > 0:
            peak_idx = int(np.argmax(magnitude))
            peak_freq = freqs[peak_idx]
            peak_amp = magnitude[peak_idx]
            rms = float(np.sqrt(np.mean(data ** 2)))

            self._lbl_peak_freq.setText(f"Peak: {peak_freq:.1f} Hz")
            self._lbl_peak_amp.setText(f"Peak Amp: {peak_amp:.2f} um")
            self._lbl_rms.setText(f"RMS: {rms:.2f} um")
