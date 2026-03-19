"""Generate sinusoidal electrode KiCad footprints for capacitive encoder.

Creates .kicad_mod files for:
  - Scale TX+/TX- excitation electrodes (sinusoidal copper traces)
  - Reader RX sense pads (4-phase: 0, 90, 180, 270 degrees)

Usage:
    python generate_electrodes.py --pitch 2.0 --length 100 --phases 4
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path


def generate_sine_points(
    pitch_mm: float,
    length_mm: float,
    amplitude_mm: float,
    phase_deg: float = 0.0,
    points_per_pitch: int = 64,
) -> list[tuple[float, float]]:
    """Generate points along a sinusoidal electrode trace."""
    n_pitches = length_mm / pitch_mm
    total_points = int(n_pitches * points_per_pitch)
    phase_rad = math.radians(phase_deg)

    points = []
    for i in range(total_points + 1):
        x = i * length_mm / total_points
        y = amplitude_mm * math.sin(2 * math.pi * x / pitch_mm + phase_rad)
        points.append((x, y))
    return points


def write_kicad_footprint(
    path: Path,
    name: str,
    traces: list[list[tuple[float, float]]],
    layer: str = "F.Cu",
    width_mm: float = 0.2,
):
    """Write a KiCad footprint file with copper traces."""
    lines = [
        f'(footprint "{name}"',
        '  (layer "F.Cu")',
        f'  (descr "Generated capacitive electrode: {name}")',
        '  (attr smd)',
    ]

    for trace in traces:
        for i in range(len(trace) - 1):
            x1, y1 = trace[i]
            x2, y2 = trace[i + 1]
            lines.append(
                f'  (fp_line (start {x1:.4f} {y1:.4f}) (end {x2:.4f} {y2:.4f}) '
                f'(stroke (width {width_mm}) (type solid)) (layer "{layer}"))'
            )

    lines.append(')')

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(lines))
    print(f"  Written: {path}")


def generate_scale_electrodes(
    output_dir: Path,
    pitch_mm: float = 2.0,
    length_mm: float = 100.0,
    finger_length_mm: float = 5.0,
    trace_width_mm: float = 0.15,
):
    """Generate TX+/TX- scale electrode footprints."""
    amplitude = finger_length_mm / 2

    # TX+ electrode (0 degrees)
    tx_pos = generate_sine_points(pitch_mm, length_mm, amplitude, phase_deg=0)
    write_kicad_footprint(
        output_dir / "scale_tx_pos.kicad_mod",
        "scale_tx_pos",
        [tx_pos],
        width_mm=trace_width_mm,
    )

    # TX- electrode (180 degrees — anti-phase)
    tx_neg = generate_sine_points(pitch_mm, length_mm, amplitude, phase_deg=180)
    write_kicad_footprint(
        output_dir / "scale_tx_neg.kicad_mod",
        "scale_tx_neg",
        [tx_neg],
        width_mm=trace_width_mm,
    )


def generate_reader_electrodes(
    output_dir: Path,
    pitch_mm: float = 2.0,
    num_pitches: int = 4,
    finger_length_mm: float = 5.0,
    trace_width_mm: float = 0.15,
):
    """Generate 4-phase reader RX electrode footprints."""
    length = pitch_mm * num_pitches
    amplitude = finger_length_mm / 2

    phases = [
        ("rx_0deg", 0),
        ("rx_90deg", 90),
        ("rx_180deg", 180),
        ("rx_270deg", 270),
    ]

    for name, phase in phases:
        points = generate_sine_points(pitch_mm, length, amplitude, phase_deg=phase)
        write_kicad_footprint(
            output_dir / f"reader_{name}.kicad_mod",
            f"reader_{name}",
            [points],
            width_mm=trace_width_mm,
        )


def main():
    parser = argparse.ArgumentParser(description="Generate capacitive encoder electrode footprints")
    parser.add_argument("--pitch", type=float, default=2.0, help="Electrode pitch in mm")
    parser.add_argument("--length", type=float, default=100.0, help="Scale length in mm")
    parser.add_argument("--finger-length", type=float, default=5.0, help="Finger length in mm")
    parser.add_argument("--width", type=float, default=0.15, help="Trace width in mm")
    parser.add_argument("--output", type=str, default=".", help="Output directory")
    args = parser.parse_args()

    output = Path(args.output)

    print("Generating scale electrodes...")
    generate_scale_electrodes(
        output / "scale",
        pitch_mm=args.pitch,
        length_mm=args.length,
        finger_length_mm=args.finger_length,
        trace_width_mm=args.width,
    )

    print("Generating reader electrodes...")
    generate_reader_electrodes(
        output / "reader",
        pitch_mm=args.pitch,
        finger_length_mm=args.finger_length,
        trace_width_mm=args.width,
    )

    print("Done.")


if __name__ == "__main__":
    main()
