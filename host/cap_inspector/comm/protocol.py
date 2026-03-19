"""FPGA command/response protocol for Cap-Scale capacitive encoder.

Commands:
    EX (4B): 'E' 'X' + freq_div[2 BE]
    MD (4B): 'M' 'D' + mode[1] + avg[1]
    ZR (2B): 'Z' 'R' — zero position

Response formats:
    Position mode (1): 0xAA 0x55 + position[4B LE signed]
    Diagnostics mode (2): 0xAA 0x55 + position[4B] + sin[2B] + cos[2B] + amplitude[2B]
"""

from __future__ import annotations

import struct

# Hardware constants
BAUD_RATE = 921_600
ADC_BITS = 12
ADC_MAX = (1 << ADC_BITS) - 1  # 4095

# Protocol constants
SYNC_MARKER = b'\xAA\x55'
POSITION_PACKET_LEN = 6    # sync(2) + position(4)
DIAG_PACKET_LEN = 12       # sync(2) + position(4) + sin(2) + cos(2) + amp(2)

# Modes
MODE_POSITION = 1
MODE_DIAGNOSTICS = 2
MODE_RAW = 3

# Default configuration
DEFAULT_FREQ_DIV = 400     # 200 kHz excitation
DEFAULT_AVG_COUNT = 16
DEFAULT_MODE = MODE_POSITION


def build_ex_command(freq_div: int = DEFAULT_FREQ_DIV) -> bytes:
    """Build 4-byte EX (excitation frequency) command."""
    cmd = bytearray(4)
    cmd[0] = 0x45  # 'E'
    cmd[1] = 0x58  # 'X'
    struct.pack_into('>H', cmd, 2, freq_div & 0xFFFF)
    return bytes(cmd)


def build_md_command(
    mode: int = DEFAULT_MODE,
    avg_count: int = DEFAULT_AVG_COUNT,
) -> bytes:
    """Build 4-byte MD (mode/averaging) command."""
    cmd = bytearray(4)
    cmd[0] = 0x4D  # 'M'
    cmd[1] = 0x44  # 'D'
    cmd[2] = mode & 0xFF
    cmd[3] = avg_count & 0xFF
    return bytes(cmd)


def build_zr_command() -> bytes:
    """Build 2-byte ZR (zero position) command."""
    return b'ZR'


def parse_position_packet(data: bytes) -> int | None:
    """Parse 6-byte position packet (sync + 4B signed LE).

    Returns position as signed 32-bit integer, or None on failure.
    """
    sync_pos = data.find(SYNC_MARKER)
    if sync_pos < 0 or len(data) < sync_pos + POSITION_PACKET_LEN:
        return None
    pos_bytes = data[sync_pos + 2:sync_pos + 6]
    return struct.unpack('<i', pos_bytes)[0]


def parse_diagnostics_packet(data: bytes) -> dict | None:
    """Parse 12-byte diagnostics packet.

    Returns dict with keys: position, sin, cos, amplitude. Or None on failure.
    """
    sync_pos = data.find(SYNC_MARKER)
    if sync_pos < 0 or len(data) < sync_pos + DIAG_PACKET_LEN:
        return None

    offset = sync_pos + 2
    position = struct.unpack('<i', data[offset:offset + 4])[0]
    sin_val = struct.unpack('<h', data[offset + 4:offset + 6])[0]
    cos_val = struct.unpack('<h', data[offset + 6:offset + 8])[0]
    amplitude = struct.unpack('<H', data[offset + 8:offset + 10])[0]

    return {
        'position': position,
        'sin': sin_val,
        'cos': cos_val,
        'amplitude': amplitude,
    }


def freq_div_to_hz(freq_div: int) -> float:
    """Convert freq_div register value to excitation frequency in Hz."""
    if freq_div == 0:
        return 0.0
    return 80_000_000.0 / freq_div


def hz_to_freq_div(freq_hz: float) -> int:
    """Convert excitation frequency in Hz to freq_div register value."""
    if freq_hz <= 0:
        return DEFAULT_FREQ_DIV
    return max(1, min(65535, round(80_000_000.0 / freq_hz)))
