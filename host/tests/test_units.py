"""Tests for unit conversion functions."""

from __future__ import annotations

import pytest

from cap_inspector.core.units import (
    counts_to_inch,
    counts_to_mm,
    counts_to_um,
    format_position,
)


class TestCountsToUm:
    def test_zero(self):
        assert counts_to_um(0) == 0.0

    def test_one_pitch(self):
        # 4096 counts = 2000 um (one full pitch)
        assert counts_to_um(4096, pitch_um=2000.0) == pytest.approx(2000.0)

    def test_half_pitch(self):
        assert counts_to_um(2048, pitch_um=2000.0) == pytest.approx(1000.0)

    def test_negative(self):
        assert counts_to_um(-4096, pitch_um=2000.0) == pytest.approx(-2000.0)

    def test_custom_pitch(self):
        # 1mm pitch
        assert counts_to_um(4096, pitch_um=1000.0) == pytest.approx(1000.0)

    def test_resolution(self):
        # Single count at 2mm pitch: 2000/4096 = 0.488 um
        result = counts_to_um(1, pitch_um=2000.0)
        assert result == pytest.approx(2000.0 / 4096, abs=0.001)


class TestCountsToMm:
    def test_one_pitch_mm(self):
        assert counts_to_mm(4096, pitch_um=2000.0) == pytest.approx(2.0)

    def test_ten_pitches(self):
        assert counts_to_mm(40960, pitch_um=2000.0) == pytest.approx(20.0)

    def test_zero(self):
        assert counts_to_mm(0) == 0.0


class TestCountsToInch:
    def test_one_inch(self):
        # 1 inch = 25400 um = 25400/2000 * 4096 = 52019.2 counts
        counts = round(25400.0 / 2000.0 * 4096)
        result = counts_to_inch(counts, pitch_um=2000.0)
        assert result == pytest.approx(1.0, abs=0.001)

    def test_zero(self):
        assert counts_to_inch(0) == 0.0

    def test_negative(self):
        result = counts_to_inch(-52019, pitch_um=2000.0)
        assert result < 0


class TestFormatPosition:
    def test_mm_format(self):
        s = format_position(4096, unit='mm', pitch_um=2000.0)
        assert 'mm' in s
        assert '2.0000' in s

    def test_um_format(self):
        s = format_position(4096, unit='um', pitch_um=2000.0)
        assert 'um' in s
        assert '2000' in s

    def test_inch_format(self):
        s = format_position(0, unit='inch')
        assert 'in' in s
        assert '0.00000' in s
