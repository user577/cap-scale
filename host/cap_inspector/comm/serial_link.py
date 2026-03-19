"""Serial port communication link for Cap-Scale encoder."""

from __future__ import annotations

import serial
import serial.tools.list_ports
from PySide6.QtCore import QThread, Signal

from cap_inspector.comm.encoder_link import EncoderLink
from cap_inspector.comm.protocol import (
    BAUD_RATE,
    DIAG_PACKET_LEN,
    MODE_DIAGNOSTICS,
    POSITION_PACKET_LEN,
    SYNC_MARKER,
    build_ex_command,
    build_md_command,
    build_zr_command,
    parse_diagnostics_packet,
    parse_position_packet,
)


class _ReaderThread(QThread):
    """Background thread that reads UART packets from the encoder."""

    position_ready = Signal(int)
    diagnostics_ready = Signal(dict)
    error = Signal(str)

    def __init__(self, ser: serial.Serial, mode: int, parent=None):
        super().__init__(parent)
        self._ser = ser
        self._mode = mode
        self._running = False

    def run(self):
        self._running = True
        buf = bytearray()

        while self._running:
            try:
                chunk = self._ser.read(max(1, self._ser.in_waiting))
                if not chunk:
                    continue
                buf.extend(chunk)

                # Process complete packets
                while True:
                    sync_pos = buf.find(SYNC_MARKER)
                    if sync_pos < 0:
                        # Keep only last byte (could be start of sync)
                        if len(buf) > 1:
                            buf = buf[-1:]
                        break

                    if self._mode == MODE_DIAGNOSTICS:
                        needed = sync_pos + DIAG_PACKET_LEN
                        if len(buf) < needed:
                            break
                        packet = bytes(buf[sync_pos:needed])
                        result = parse_diagnostics_packet(packet)
                        if result is not None:
                            self.diagnostics_ready.emit(result)
                        buf = buf[needed:]
                    else:
                        needed = sync_pos + POSITION_PACKET_LEN
                        if len(buf) < needed:
                            break
                        packet = bytes(buf[sync_pos:needed])
                        result = parse_position_packet(packet)
                        if result is not None:
                            self.position_ready.emit(result)
                        buf = buf[needed:]

            except serial.SerialException as e:
                self.error.emit(str(e))
                break
            except Exception as e:
                self.error.emit(f"Reader error: {e}")
                break

    def stop(self):
        self._running = False
        self.wait(2000)


class SerialLink(EncoderLink):
    """Concrete serial port link to Cap-Scale FPGA."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._ser: serial.Serial | None = None
        self._reader: _ReaderThread | None = None

    @staticmethod
    def list_ports() -> list[dict]:
        """List available serial ports."""
        ports = []
        for p in serial.tools.list_ports.comports():
            ports.append({
                'device': p.device,
                'description': p.description or '',
                'hwid': p.hwid or '',
            })
        return ports

    def connect(self, port: str) -> bool:
        try:
            self._ser = serial.Serial(
                port=port,
                baudrate=BAUD_RATE,
                timeout=0.1,
                write_timeout=1.0,
            )
            self._port_name = port
            self._connected = True
            self.connection_changed.emit(True)
            return True
        except serial.SerialException as e:
            self.error_occurred.emit(str(e))
            return False

    def disconnect(self) -> None:
        self.stop_streaming()
        if self._ser and self._ser.is_open:
            self._ser.close()
        self._ser = None
        self._connected = False
        self._port_name = ''
        self.connection_changed.emit(False)

    def send_ex_command(self, freq_div: int) -> None:
        self._write(build_ex_command(freq_div))

    def send_md_command(self, mode: int, avg_count: int) -> None:
        self._write(build_md_command(mode, avg_count))

    def send_zero(self) -> None:
        self._write(build_zr_command())

    def start_streaming(self, mode: int) -> None:
        if not self._connected or self._ser is None:
            return
        self.stop_streaming()
        self.send_md_command(mode, 16)
        self._reader = _ReaderThread(self._ser, mode, self)
        self._reader.position_ready.connect(self.position_received.emit)
        self._reader.diagnostics_ready.connect(self.diagnostics_received.emit)
        self._reader.error.connect(self.error_occurred.emit)
        self._reader.start()

    def stop_streaming(self) -> None:
        if self._reader is not None:
            self._reader.stop()
            self._reader = None

    def _write(self, data: bytes) -> None:
        if self._ser and self._ser.is_open:
            try:
                self._ser.write(data)
            except serial.SerialException as e:
                self.error_occurred.emit(str(e))
