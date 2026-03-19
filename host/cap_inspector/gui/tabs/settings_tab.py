"""Settings tab — encoder configuration, pitch, logging."""

from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDoubleSpinBox,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QRadioButton,
    QSlider,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from cap_inspector.comm.encoder_link import EncoderLink
from cap_inspector.comm.protocol import (
    DEFAULT_AVG_COUNT,
    DEFAULT_FREQ_DIV,
    MODE_DIAGNOSTICS,
    MODE_POSITION,
    MODE_RAW,
    freq_div_to_hz,
    hz_to_freq_div,
)
from cap_inspector.core.config import AppConfig


class SettingsTab(QWidget):
    """Encoder settings: excitation frequency, averaging, mode, pitch, logging."""

    logging_toggled = Signal(bool)

    def __init__(self, link: EncoderLink, config: AppConfig, parent=None):
        super().__init__(parent)
        self._link = link
        self._config = config

        self._build_ui()
        self._connect_signals()

    def _build_ui(self):
        layout = QVBoxLayout(self)

        # Excitation frequency
        freq_group = QGroupBox("Excitation Frequency")
        freq_layout = QVBoxLayout()

        freq_row = QHBoxLayout()
        self._slider_freq = QSlider(Qt.Orientation.Horizontal)
        self._slider_freq.setRange(100, 2000)  # freq_div values
        self._slider_freq.setValue(self._config.encoder.freq_div)
        self._lbl_freq = QLabel(f"{freq_div_to_hz(self._config.encoder.freq_div) / 1000:.1f} kHz")
        freq_row.addWidget(QLabel("Freq Div:"))
        freq_row.addWidget(self._slider_freq)
        freq_row.addWidget(self._lbl_freq)
        freq_layout.addLayout(freq_row)

        self._btn_apply_freq = QPushButton("Apply Frequency")
        freq_layout.addWidget(self._btn_apply_freq)

        freq_group.setLayout(freq_layout)
        layout.addWidget(freq_group)

        # Averaging
        avg_group = QGroupBox("Averaging")
        avg_layout = QHBoxLayout()
        avg_layout.addWidget(QLabel("Samples per channel:"))
        self._spin_avg = QSpinBox()
        self._spin_avg.setRange(1, 255)
        self._spin_avg.setValue(self._config.encoder.avg_count)
        avg_layout.addWidget(self._spin_avg)
        avg_layout.addStretch()
        avg_group.setLayout(avg_layout)
        layout.addWidget(avg_group)

        # Mode selection
        mode_group = QGroupBox("Output Mode")
        mode_layout = QHBoxLayout()
        self._radio_pos = QRadioButton("Position (6B)")
        self._radio_diag = QRadioButton("Diagnostics (12B)")
        self._radio_raw = QRadioButton("Raw ADC")
        self._radio_pos.setChecked(True)
        mode_layout.addWidget(self._radio_pos)
        mode_layout.addWidget(self._radio_diag)
        mode_layout.addWidget(self._radio_raw)
        mode_layout.addStretch()

        self._btn_apply_mode = QPushButton("Apply Mode")
        mode_layout.addWidget(self._btn_apply_mode)

        mode_group.setLayout(mode_layout)
        layout.addWidget(mode_group)

        # Scale configuration
        scale_group = QGroupBox("Scale Configuration")
        scale_layout = QFormLayout()
        self._spin_pitch = QDoubleSpinBox()
        self._spin_pitch.setRange(0.1, 100000.0)
        self._spin_pitch.setDecimals(1)
        self._spin_pitch.setSuffix(" um")
        self._spin_pitch.setValue(self._config.scale.pitch_um)
        scale_layout.addRow("Electrode Pitch:", self._spin_pitch)
        scale_group.setLayout(scale_layout)
        layout.addWidget(scale_group)

        # Data logging
        log_group = QGroupBox("Data Logging")
        log_layout = QHBoxLayout()
        self._chk_logging = QCheckBox("Enable CSV logging")
        self._chk_logging.setChecked(self._config.data_logging)
        log_layout.addWidget(self._chk_logging)
        log_layout.addStretch()
        log_group.setLayout(log_layout)
        layout.addWidget(log_group)

        layout.addStretch()

    def _connect_signals(self):
        self._slider_freq.valueChanged.connect(self._on_freq_changed)
        self._btn_apply_freq.clicked.connect(self._apply_freq)
        self._btn_apply_mode.clicked.connect(self._apply_mode)
        self._spin_pitch.valueChanged.connect(self._on_pitch_changed)
        self._chk_logging.toggled.connect(self._on_logging_toggled)

    def _on_freq_changed(self, val: int):
        hz = freq_div_to_hz(val)
        self._lbl_freq.setText(f"{hz / 1000:.1f} kHz")

    def _apply_freq(self):
        freq_div = self._slider_freq.value()
        self._config.encoder.freq_div = freq_div
        if self._link.is_connected:
            self._link.send_ex_command(freq_div)

    def _apply_mode(self):
        if self._radio_pos.isChecked():
            mode = MODE_POSITION
        elif self._radio_diag.isChecked():
            mode = MODE_DIAGNOSTICS
        else:
            mode = MODE_RAW

        avg = self._spin_avg.value()
        self._config.encoder.mode = mode
        self._config.encoder.avg_count = avg
        if self._link.is_connected:
            self._link.send_md_command(mode, avg)

    def _on_pitch_changed(self, val: float):
        self._config.scale.pitch_um = val

    def _on_logging_toggled(self, checked: bool):
        self._config.data_logging = checked
        self.logging_toggled.emit(checked)
