"""Abstract base class for encoder communication link."""

from __future__ import annotations

from abc import ABC, abstractmethod

from PySide6.QtCore import QObject, Signal


class EncoderLink(QObject, ABC):
    """Base class for FPGA encoder communication."""

    position_received = Signal(int)          # Signed 32-bit position
    diagnostics_received = Signal(dict)      # {position, sin, cos, amplitude}
    connection_changed = Signal(bool)
    error_occurred = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._connected = False
        self._port_name = ''

    @property
    def is_connected(self) -> bool:
        return self._connected

    @property
    def port_name(self) -> str:
        return self._port_name

    @abstractmethod
    def connect(self, port: str) -> bool:
        ...

    @abstractmethod
    def disconnect(self) -> None:
        ...

    @abstractmethod
    def send_ex_command(self, freq_div: int) -> None:
        ...

    @abstractmethod
    def send_md_command(self, mode: int, avg_count: int) -> None:
        ...

    @abstractmethod
    def send_zero(self) -> None:
        ...

    @abstractmethod
    def start_streaming(self, mode: int) -> None:
        ...

    @abstractmethod
    def stop_streaming(self) -> None:
        ...
