"""Generate 2D atan2 lookup table for position_calc.v.

Creates a 64x64 = 4096 entry LUT indexed by the upper 6 bits of |sin| and |cos|.
Each entry is the first-quadrant angle (0-1023 counts, mapping to 0-90 degrees).
The Verilog module handles quadrant correction.

Output: src/atan2_lut.hex — 4096 lines of 3-digit hex values (12-bit).
"""

from __future__ import annotations

import math
from pathlib import Path


def generate_atan2_lut(size: int = 64) -> list[int]:
    """Generate 2D atan2 LUT.

    For each (si, ci) in [0..63] × [0..63]:
        angle = atan2(si, ci) mapped to 0-1023 (first quadrant, 0-90 degrees)

    Index = si * 64 + ci
    """
    lut = []
    for si in range(size):
        for ci in range(size):
            if si == 0 and ci == 0:
                angle = 0
            else:
                theta_rad = math.atan2(si, ci)  # 0 to pi/2 for positive inputs
                # Map to 0-1023 (first quadrant = 1024 counts)
                angle = round(theta_rad * 4096 / (2 * math.pi))
            lut.append(angle)
    return lut


def write_hex_file(lut: list[int], path: Path) -> None:
    """Write LUT as hex file for $readmemh."""
    with open(path, 'w') as f:
        for val in lut:
            f.write(f"{val:03X}\n")
    print(f"Written {len(lut)} entries to {path}")


def verify(lut: list[int]) -> None:
    """Print verification table."""
    size = 64
    print(f"\nVerification (64x64 = {len(lut)} entries):")
    print(f"  {'si':>4s} {'ci':>4s}  {'atan2(deg)':>10s}  {'LUT':>5s}  {'Expected':>8s}")

    test_cases = [
        (0, 63),   # 0 degrees
        (16, 63),  # ~14 degrees
        (32, 32),  # 45 degrees
        (63, 32),  # ~63 degrees
        (63, 0),   # 90 degrees
        (63, 63),  # 45 degrees
        (0, 0),    # undefined (0)
    ]

    for si, ci in test_cases:
        idx = si * size + ci
        if si == 0 and ci == 0:
            theta = 0
        else:
            theta = math.degrees(math.atan2(si, ci))
        expected = round(math.atan2(si, ci) * 4096 / (2 * math.pi)) if (si or ci) else 0
        print(f"  {si:4d} {ci:4d}  {theta:10.2f}  {lut[idx]:5d}  {expected:8d}")

    # Check max value
    print(f"\n  Max LUT value: {max(lut)} (should be ~1024 for atan2(63,0))")
    print(f"  Min LUT value: {min(lut)} (should be 0)")


def main():
    proj_root = Path(__file__).parent.parent
    lut = generate_atan2_lut()

    # Write hex file
    hex_path = proj_root / "src" / "atan2_lut.hex"
    write_hex_file(lut, hex_path)

    # Also copy to testbench dir for simulation
    tb_path = proj_root / "testbench" / "atan2_lut.hex"
    write_hex_file(lut, tb_path)

    verify(lut)


if __name__ == "__main__":
    main()
