"""Calibration routines for capacitive encoder signal correction."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np


@dataclass
class CalibrationData:
    """Stores and applies sin/cos signal correction."""

    sin_offset: float = 0.0
    cos_offset: float = 0.0
    sin_gain: float = 1.0
    cos_gain: float = 1.0
    phase_error: float = 0.0      # Radians
    lut: list[float] = field(default_factory=list)  # Angle correction LUT
    known_length_mm: float = 0.0
    measured_counts: int = 0

    def correct(self, sin_val: float, cos_val: float) -> tuple[float, float]:
        """Apply offset, gain, and phase correction to raw sin/cos."""
        s = (sin_val - self.sin_offset) * self.sin_gain
        c = (cos_val - self.cos_offset) * self.cos_gain
        # Phase correction: rotate by -phase_error
        if self.phase_error != 0.0:
            cos_pe = np.cos(-self.phase_error)
            sin_pe = np.sin(-self.phase_error)
            s, c = s * cos_pe - c * sin_pe, s * sin_pe + c * cos_pe
        return s, c

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            'sin_offset': self.sin_offset,
            'cos_offset': self.cos_offset,
            'sin_gain': self.sin_gain,
            'cos_gain': self.cos_gain,
            'phase_error': self.phase_error,
            'lut': self.lut,
            'known_length_mm': self.known_length_mm,
            'measured_counts': self.measured_counts,
        }
        path.write_text(json.dumps(data, indent=2))

    @classmethod
    def load(cls, path: Path) -> CalibrationData:
        if not path.exists():
            return cls()
        try:
            data = json.loads(path.read_text())
            return cls(**{k: v for k, v in data.items()
                         if k in cls.__dataclass_fields__})
        except (json.JSONDecodeError, TypeError):
            return cls()


def compute_calibration(sin_samples: np.ndarray, cos_samples: np.ndarray) -> CalibrationData:
    """Compute calibration from a sweep of sin/cos samples over travel.

    Assumes samples cover at least one full pitch (360 degrees of signal).
    """
    cal = CalibrationData()
    cal.sin_offset = float(np.mean(sin_samples))
    cal.cos_offset = float(np.mean(cos_samples))

    sin_centered = sin_samples - cal.sin_offset
    cos_centered = cos_samples - cal.cos_offset

    sin_amp = float(np.std(sin_centered) * np.sqrt(2))
    cos_amp = float(np.std(cos_centered) * np.sqrt(2))

    if sin_amp > 0:
        cal.sin_gain = 1.0 / sin_amp
    if cos_amp > 0:
        cal.cos_gain = 1.0 / cos_amp

    # Phase error from cross-correlation
    normalized_sin = sin_centered * cal.sin_gain
    normalized_cos = cos_centered * cal.cos_gain
    cross = float(np.mean(normalized_sin * normalized_cos))
    cal.phase_error = np.arcsin(np.clip(cross, -1, 1))

    return cal
