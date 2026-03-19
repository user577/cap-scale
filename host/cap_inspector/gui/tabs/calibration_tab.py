"""Calibration tab — sweep, amplitude vs frequency, correction table."""

from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
import pyqtgraph as pg
from PySide6.QtCore import QTimer
from PySide6.QtWidgets import (
    QDoubleSpinBox,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from cap_inspector.comm.encoder_link import EncoderLink
from cap_inspector.comm.protocol import MODE_DIAGNOSTICS
from cap_inspector.core.calibration import CalibrationData, compute_calibration


class CalibrationTab(QWidget):
    """Calibration sweep, amplitude vs frequency plot, and correction table."""

    def __init__(self, link: EncoderLink, parent=None):
        super().__init__(parent)
        self._link = link
        self._cal = CalibrationData()
        self._sin_samples: list[float] = []
        self._cos_samples: list[float] = []
        self._sweeping = False

        self._build_ui()
        self._connect_signals()

    def _build_ui(self):
        layout = QVBoxLayout(self)

        # Sweep controls
        sweep_group = QGroupBox("Signal Sweep Calibration")
        sweep_layout = QVBoxLayout()

        btn_row = QHBoxLayout()
        self._btn_sweep = QPushButton("Start Sweep")
        self._btn_sweep_stop = QPushButton("Stop & Compute")
        self._btn_sweep_stop.setEnabled(False)
        self._btn_save = QPushButton("Save Calibration")
        self._btn_load = QPushButton("Load Calibration")

        btn_row.addWidget(self._btn_sweep)
        btn_row.addWidget(self._btn_sweep_stop)
        btn_row.addWidget(self._btn_save)
        btn_row.addWidget(self._btn_load)
        btn_row.addStretch()
        sweep_layout.addLayout(btn_row)

        self._lbl_sweep_status = QLabel("Move encoder slowly over full travel during sweep.")
        sweep_layout.addWidget(self._lbl_sweep_status)

        sweep_group.setLayout(sweep_layout)
        layout.addWidget(sweep_group)

        # Amplitude vs position plot
        self._amp_plot = pg.PlotWidget(title="Sin/Cos Signal During Sweep")
        self._amp_plot.setLabel('bottom', 'Sample')
        self._amp_plot.setLabel('left', 'Amplitude')
        self._amp_plot.showGrid(x=True, y=True, alpha=0.3)
        self._sin_curve = self._amp_plot.plot(pen=pg.mkPen('#ff4444', width=1), name='Sin')
        self._cos_curve = self._amp_plot.plot(pen=pg.mkPen('#4444ff', width=1), name='Cos')
        self._amp_plot.addLegend()
        layout.addWidget(self._amp_plot)

        # Known-length calibration
        cal_group = QGroupBox("Known Length Calibration")
        cal_layout = QHBoxLayout()
        cal_layout.addWidget(QLabel("Known length (mm):"))
        self._spin_length = QDoubleSpinBox()
        self._spin_length.setRange(0.1, 10000.0)
        self._spin_length.setDecimals(3)
        self._spin_length.setValue(25.400)
        cal_layout.addWidget(self._spin_length)
        self._btn_cal_measure = QPushButton("Measure")
        cal_layout.addWidget(self._btn_cal_measure)
        cal_layout.addStretch()
        cal_group.setLayout(cal_layout)
        layout.addWidget(cal_group)

        # Correction table display
        table_group = QGroupBox("Correction Parameters")
        table_layout = QVBoxLayout()
        self._txt_correction = QTextEdit()
        self._txt_correction.setReadOnly(True)
        self._txt_correction.setMaximumHeight(120)
        self._txt_correction.setStyleSheet("font-family: Consolas; font-size: 11px;")
        self._update_correction_display()
        table_layout.addWidget(self._txt_correction)
        table_group.setLayout(table_layout)
        layout.addWidget(table_group)

    def _connect_signals(self):
        self._btn_sweep.clicked.connect(self._start_sweep)
        self._btn_sweep_stop.clicked.connect(self._stop_sweep)
        self._btn_save.clicked.connect(self._save_cal)
        self._btn_load.clicked.connect(self._load_cal)
        self._link.diagnostics_received.connect(self._on_diagnostics)

    def _start_sweep(self):
        if not self._link.is_connected:
            return
        self._sin_samples.clear()
        self._cos_samples.clear()
        self._sweeping = True
        self._link.start_streaming(MODE_DIAGNOSTICS)
        self._btn_sweep.setEnabled(False)
        self._btn_sweep_stop.setEnabled(True)
        self._lbl_sweep_status.setText("Sweeping... Move encoder slowly over full travel.")

    def _stop_sweep(self):
        self._link.stop_streaming()
        self._sweeping = False
        self._btn_sweep.setEnabled(True)
        self._btn_sweep_stop.setEnabled(False)

        if len(self._sin_samples) > 50:
            sin_arr = np.array(self._sin_samples)
            cos_arr = np.array(self._cos_samples)
            self._cal = compute_calibration(sin_arr, cos_arr)
            self._update_correction_display()
            self._lbl_sweep_status.setText(
                f"Calibration computed from {len(self._sin_samples)} samples."
            )
        else:
            self._lbl_sweep_status.setText("Not enough samples. Try again.")

    def _on_diagnostics(self, data: dict):
        if self._sweeping:
            self._sin_samples.append(data['sin'])
            self._cos_samples.append(data['cos'])

            # Update plot periodically
            if len(self._sin_samples) % 50 == 0:
                self._sin_curve.setData(self._sin_samples)
                self._cos_curve.setData(self._cos_samples)

    def _update_correction_display(self):
        self._txt_correction.setPlainText(
            f"Sin Offset:     {self._cal.sin_offset:+.1f}\n"
            f"Cos Offset:     {self._cal.cos_offset:+.1f}\n"
            f"Sin Gain:       {self._cal.sin_gain:.4f}\n"
            f"Cos Gain:       {self._cal.cos_gain:.4f}\n"
            f"Phase Error:    {np.degrees(self._cal.phase_error):.2f} deg"
        )

    def _save_cal(self):
        cal_path = Path.home() / '.cap-scale' / 'calibration.json'
        self._cal.save(cal_path)
        self._lbl_sweep_status.setText(f"Saved to {cal_path}")

    def _load_cal(self):
        cal_path = Path.home() / '.cap-scale' / 'calibration.json'
        self._cal = CalibrationData.load(cal_path)
        self._update_correction_display()
        self._lbl_sweep_status.setText(f"Loaded from {cal_path}")
