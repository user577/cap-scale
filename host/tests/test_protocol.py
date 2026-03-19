"""Tests for FPGA command/response protocol."""

from __future__ import annotations

import struct

import pytest

from cap_inspector.comm.protocol import (
    DIAG_PACKET_LEN,
    MODE_DIAGNOSTICS,
    MODE_POSITION,
    POSITION_PACKET_LEN,
    SYNC_MARKER,
    build_ex_command,
    build_md_command,
    build_zr_command,
    freq_div_to_hz,
    hz_to_freq_div,
    parse_diagnostics_packet,
    parse_position_packet,
)


class TestCommandBuilders:
    def test_ex_command_default(self):
        cmd = build_ex_command()
        assert cmd[:2] == b'EX'
        assert len(cmd) == 4
        freq_div = struct.unpack('>H', cmd[2:4])[0]
        assert freq_div == 400

    def test_ex_command_custom(self):
        cmd = build_ex_command(800)
        freq_div = struct.unpack('>H', cmd[2:4])[0]
        assert freq_div == 800

    def test_md_command_default(self):
        cmd = build_md_command()
        assert cmd[:2] == b'MD'
        assert len(cmd) == 4
        assert cmd[2] == MODE_POSITION
        assert cmd[3] == 16

    def test_md_command_custom(self):
        cmd = build_md_command(mode=2, avg_count=32)
        assert cmd[2] == 2
        assert cmd[3] == 32

    def test_zr_command(self):
        cmd = build_zr_command()
        assert cmd == b'ZR'
        assert len(cmd) == 2


class TestPacketParsers:
    def test_parse_position_positive(self):
        pos = 12345
        packet = SYNC_MARKER + struct.pack('<i', pos)
        result = parse_position_packet(packet)
        assert result == pos

    def test_parse_position_negative(self):
        pos = -54321
        packet = SYNC_MARKER + struct.pack('<i', pos)
        result = parse_position_packet(packet)
        assert result == pos

    def test_parse_position_zero(self):
        packet = SYNC_MARKER + struct.pack('<i', 0)
        result = parse_position_packet(packet)
        assert result == 0

    def test_parse_position_with_leading_garbage(self):
        pos = 999
        packet = b'\x00\xFF\x42' + SYNC_MARKER + struct.pack('<i', pos)
        result = parse_position_packet(packet)
        assert result == pos

    def test_parse_position_too_short(self):
        packet = SYNC_MARKER + b'\x00'
        result = parse_position_packet(packet)
        assert result is None

    def test_parse_position_no_sync(self):
        packet = b'\x00\x00\x00\x00\x00\x00'
        result = parse_position_packet(packet)
        assert result is None

    def test_parse_diagnostics(self):
        pos = 5000
        sin_val = -1234
        cos_val = 4567
        amp = 3000
        ch0, ch1, ch2, ch3 = 1000, 2000, -1000, -2000
        packet = (
            SYNC_MARKER
            + struct.pack('<i', pos)
            + struct.pack('<h', sin_val)
            + struct.pack('<h', cos_val)
            + struct.pack('<H', amp)
            + struct.pack('<h', ch0)
            + struct.pack('<h', ch1)
            + struct.pack('<h', ch2)
            + struct.pack('<h', ch3)
        )
        result = parse_diagnostics_packet(packet)
        assert result is not None
        assert result['position'] == pos
        assert result['sin'] == sin_val
        assert result['cos'] == cos_val
        assert result['amplitude'] == amp
        assert result['ch0'] == ch0
        assert result['ch1'] == ch1
        assert result['ch2'] == ch2
        assert result['ch3'] == ch3

    def test_parse_diagnostics_too_short(self):
        packet = SYNC_MARKER + b'\x00' * 10  # Need 18 bytes after sync
        result = parse_diagnostics_packet(packet)
        assert result is None

    def test_roundtrip_endianness(self):
        """Verify little-endian position survives encode/decode."""
        for pos in [0, 1, -1, 2**31 - 1, -(2**31), 0x7FFFFFFF]:
            packet = SYNC_MARKER + struct.pack('<i', pos)
            result = parse_position_packet(packet)
            assert result == pos, f"Failed for {pos}: got {result}"


class TestFrequencyConversion:
    def test_default_freq(self):
        hz = freq_div_to_hz(400)
        assert hz == 200_000.0

    def test_freq_roundtrip(self):
        for freq in [100_000, 200_000, 500_000, 1_000_000]:
            div = hz_to_freq_div(freq)
            recovered = freq_div_to_hz(div)
            assert abs(recovered - freq) / freq < 0.01

    def test_zero_freq_div(self):
        assert freq_div_to_hz(0) == 0.0

    def test_zero_freq_hz(self):
        div = hz_to_freq_div(0)
        assert div == 400  # Default
