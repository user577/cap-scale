"""Main application window for Cap-Scale Inspector."""

from __future__ import annotations

from PySide6.QtWidgets import (
    QComboBox,
    QLabel,
    QMainWindow,
    QPushButton,
    QStatusBar,
    QTabWidget,
    QToolBar,
)

from cap_inspector.comm.serial_link import SerialLink
from cap_inspector.core.config import AppConfig
from cap_inspector.core.data_logger import DataLogger
from cap_inspector.gui.tabs.calibration_tab import CalibrationTab
from cap_inspector.gui.tabs.live_position_tab import LivePositionTab
from cap_inspector.gui.tabs.runout_tab import RunoutTab
from cap_inspector.gui.tabs.settings_tab import SettingsTab
from cap_inspector.gui.tabs.signal_tab import SignalTab
from cap_inspector.gui.tabs.vibration_tab import VibrationTab


class MainWindow(QMainWindow):
    """Cap-Scale Inspector main window with 6 tabs."""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Cap-Scale Inspector")
        self.resize(1200, 700)

        self._link = SerialLink(self)
        self._config = AppConfig.load()
        self._logger = DataLogger()

        self._build_toolbar()
        self._build_tabs()
        self._build_statusbar()
        self._connect_signals()
        self._refresh_ports()

    def _build_toolbar(self):
        toolbar = QToolBar("Connection")
        toolbar.setMovable(False)
        self.addToolBar(toolbar)

        toolbar.addWidget(QLabel(" Port: "))
        self._combo_port = QComboBox()
        self._combo_port.setMinimumWidth(120)
        toolbar.addWidget(self._combo_port)

        self._btn_refresh = QPushButton("Refresh")
        toolbar.addWidget(self._btn_refresh)

        self._btn_connect = QPushButton("Connect")
        toolbar.addWidget(self._btn_connect)

        self._btn_disconnect = QPushButton("Disconnect")
        self._btn_disconnect.setEnabled(False)
        toolbar.addWidget(self._btn_disconnect)

    def _build_tabs(self):
        self._tabs = QTabWidget()
        self.setCentralWidget(self._tabs)

        self._position_tab = LivePositionTab(self._link, self._config)
        self._signal_tab = SignalTab(self._link)
        self._vibration_tab = VibrationTab(self._link, self._config)
        self._runout_tab = RunoutTab(self._link)
        self._calibration_tab = CalibrationTab(self._link)
        self._settings_tab = SettingsTab(self._link, self._config)

        self._tabs.addTab(self._position_tab, "Position")
        self._tabs.addTab(self._signal_tab, "Signal")
        self._tabs.addTab(self._vibration_tab, "Vibration")
        self._tabs.addTab(self._runout_tab, "Runout")
        self._tabs.addTab(self._calibration_tab, "Calibration")
        self._tabs.addTab(self._settings_tab, "Settings")

    def _build_statusbar(self):
        self._statusbar = QStatusBar()
        self.setStatusBar(self._statusbar)
        self._lbl_conn_status = QLabel("Disconnected")
        self._statusbar.addPermanentWidget(self._lbl_conn_status)

    def _connect_signals(self):
        self._btn_refresh.clicked.connect(self._refresh_ports)
        self._btn_connect.clicked.connect(self._connect)
        self._btn_disconnect.clicked.connect(self._disconnect)
        self._link.connection_changed.connect(self._on_connection_changed)
        self._link.error_occurred.connect(self._on_error)
        self._link.position_received.connect(self._on_log_position)
        self._link.diagnostics_received.connect(self._on_log_diagnostics)
        self._settings_tab.logging_toggled.connect(self._on_logging_toggled)

    def _refresh_ports(self):
        self._combo_port.clear()
        ports = SerialLink.list_ports()
        for p in ports:
            label = f"{p['device']}  ({p['description']})" if p['description'] else p['device']
            self._combo_port.addItem(label, p['device'])

    def _connect(self):
        port = self._combo_port.currentData()
        if not port:
            self._statusbar.showMessage("No port selected", 3000)
            return
        ok = self._link.connect(port)
        if not ok:
            self._statusbar.showMessage(f"Failed to connect to {port}", 3000)

    def _disconnect(self):
        self._link.stop_streaming()
        self._link.disconnect()

    def _on_connection_changed(self, connected: bool):
        self._btn_connect.setEnabled(not connected)
        self._btn_disconnect.setEnabled(connected)
        self._combo_port.setEnabled(not connected)
        if connected:
            self._lbl_conn_status.setText(f"Connected: {self._link.port_name}")
            self._statusbar.showMessage("Connected", 2000)
        else:
            self._lbl_conn_status.setText("Disconnected")

    def _on_error(self, msg: str):
        self._statusbar.showMessage(f"Error: {msg}", 5000)

    def _on_log_position(self, pos: int):
        self._logger.log_position(pos)

    def _on_log_diagnostics(self, data: dict):
        self._logger.log_diagnostics(data)

    def _on_logging_toggled(self, enabled: bool):
        if enabled:
            diag = self._config.encoder.mode == 2
            path = self._logger.start(diagnostics_mode=diag)
            self._statusbar.showMessage(f"Logging to {path}", 3000)
        else:
            self._logger.stop()
            self._statusbar.showMessage("Logging stopped", 2000)

    def closeEvent(self, event):
        self._logger.stop()
        self._link.stop_streaming()
        self._link.disconnect()
        self._config.save()
        super().closeEvent(event)
