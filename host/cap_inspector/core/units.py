"""Unit conversion for encoder position counts."""

from __future__ import annotations


def counts_to_um(counts: int, pitch_um: float = 2000.0, counts_per_pitch: int = 4096) -> float:
    """Convert raw encoder counts to micrometers."""
    return counts * pitch_um / counts_per_pitch


def counts_to_mm(counts: int, pitch_um: float = 2000.0, counts_per_pitch: int = 4096) -> float:
    """Convert raw encoder counts to millimeters."""
    return counts_to_um(counts, pitch_um, counts_per_pitch) / 1000.0


def counts_to_inch(counts: int, pitch_um: float = 2000.0, counts_per_pitch: int = 4096) -> float:
    """Convert raw encoder counts to inches."""
    return counts_to_um(counts, pitch_um, counts_per_pitch) / 25400.0


def format_position(counts: int, unit: str = 'mm',
                    pitch_um: float = 2000.0, counts_per_pitch: int = 4096) -> str:
    """Format position with appropriate unit suffix and decimal places."""
    if unit == 'um':
        val = counts_to_um(counts, pitch_um, counts_per_pitch)
        return f"{val:.1f} um"
    elif unit == 'inch':
        val = counts_to_inch(counts, pitch_um, counts_per_pitch)
        return f"{val:.5f} in"
    else:  # mm
        val = counts_to_mm(counts, pitch_um, counts_per_pitch)
        return f"{val:.4f} mm"
