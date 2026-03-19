# Cap-Scale PCB Design & Component Selection Guide

## Context

The cap-scale FPGA firmware and host software are complete. The next step is fabricating the 3 custom PCBs (scale, reader, amp board) and selecting analog components. This guide covers every design decision that affects measurement stability and accuracy, with quantified impacts and specific part recommendations.

## System Signal Chain

```
FPGA TX_POS/TX_NEG (3.3V LVCMOS, 200 kHz square wave, DRIVE=8)
  → Scale PCB (TX+/TX- sinusoidal copper electrodes, 2mm pitch)
    ↕ 0.3–0.5mm air gap (~0.1–1 pF coupling per pad)
  → Reader PCB (4-phase RX: 0°/90°/180°/270°, 4 pitch periods)
    → 5cm cable (low-capacitance wire)
  → Amp Board (charge amplifier: Cf=2.2pF, Rf=10MΩ → CD4052 mux → RC filter)
    → AD9226 ADC (12-bit, 3.2 MHz sample rate)
      → FPGA sync demod (20-bit accumulators, 16 samples/ch)
        → atan2 LUT (64×64, 4096 counts/pitch → 0.49 µm/count)
```

---

## 1. Scale PCB

### Substrate
- **Use FR4 1.6mm, 2-layer** for the first prototype. Cost: $5–10 at JLCPCB.
- FR4 CTE = 14 ppm/°C → a 200mm scale drifts **2.8 µm/°C**. Over a 10°C shop-floor swing, that's 28 µm — unacceptable without compensation.
- **Mitigation**: Add a **10K NTC thermistor** (Murata NCP15XH103F03RC, $0.10) to the scale PCB. Apply software correction: `pos_corrected = pos_raw × (1 - 14e-6 × (T - T_ref))`. Residual error with ±0.5°C thermistor accuracy: ~1.4 µm on 200mm.
- **Upgrade path**: Aluminum-backed FR4 (MCPCB, ~8 ppm/°C, 2× cost) or Rogers RO4003C (~10 ppm/°C, 3× cost) for scales >200mm.

### Surface Finish
- **Use ENIG** (Electroless Nickel Immersion Gold). Flat (±0.5 µm), corrosion-resistant, ideal for exposed electrode surfaces.
- Avoid OSP (oxidizes in weeks), HASL (±3–8 µm surface variation, lumpy profile).

### Layer Stackup
- **Layer 1 (top)**: TX+ and TX- sinusoidal electrodes + grounded guard traces between them (0.1–0.15mm width, connected to L2 ground via stitching vias every 5mm).
- **Layer 2 (bottom)**: Solid ground plane. Critical — shields electrodes from parasitic coupling to mounting structure. Reduces environmental sensitivity by ~15–20 dB.

### Electrode Geometry
- **Sinusoidal profile is correct** (already in `generate_electrodes.py`). 64 points/pitch gives chordal error of ~0.3 µm — negligible.
- Trapezoidal would inject 33% 3rd harmonic → ~53-count cyclic error (~26 µm). Unacceptable. Keep sinusoidal.
- **Guard electrodes**: Add grounded traces between TX+ and TX- to reduce direct TX crosstalk by ~20 dB.

### Solder Mask
- **Open solder mask over the electrode region** — exposes ENIG-finished copper for maximum coupling and minimum thickness variation.
- Keep solder mask on connector pads and non-electrode areas.

### Pitch Accuracy
- Standard PCB placement accuracy: ±25–50 µm. Relative pitch accuracy (within one file) is much better: ~1–5 µm.
- **Request "controlled impedance" class fabrication** for tighter scaling (±25 ppm).
- A 0.1% pitch error accumulates to 100 µm over 100mm. The 4-pitch reader averaging reduces single-pitch errors by √4 = 2×.
- **Add fiducial marks** at known positions for post-fab calibration.

### Maximum Length
- **Practical limit: ~500mm on FR4.** Thermal drift, panel size (18×24"), and sag become limiting. For longer travel, use segmented scales or absolute encoding.

---

## 2. Reader PCB

### Pitch Coverage
- **4 pitch periods (8mm)** is the right starting point. Averages out local pitch errors (÷2), provides ~0.4–2 pF total coupling per phase.
- If SNR is insufficient, increase to 8 pitches. Don't exceed 8 (tilt sensitivity scales with reader length).

### Pad Geometry
- **Use filled copper zones** (sinusoidal boundary), not single 0.15mm traces. Filled zones capture ~10× more charge.
- Modify `generate_electrodes.py` to output copper zone polygons bounded by sinusoidal edges.
- RX pad width (perpendicular to travel): 4–5mm, matching TX finger length.

### Ground Shielding
- **Guard traces between each RX phase pair** (0.1–0.15mm grounded traces). Without guards, inter-phase crosstalk is 1–5% → ~3.4 µm error. With guards, crosstalk drops below 0.1%.
- **Solid ground plane on layer 2** of the reader.
- Stitching vias every 2–3mm connecting guards to ground.

### Cable to Amp Board
- **Keep under 5cm.** Coax cable adds ~100 pF/m; even 10cm adds 10 pF — 10× the source capacitance, killing signal amplitude.
- Use solid hookup wire or FEP-insulated wire (15–30 pF/m). Not ribbon cable.
- 4 signal wires (one per RX phase) + ground + TX+/TX-.
- If cable must exceed 10cm: either implement a **driven shield** (bootstrap) or **mount the TIA directly on the reader PCB**.

---

## 3. Charge Amplifier (TIA)

### Circuit (per channel)
```
            Cf = 2.2 pF (COG/NPO 0402)
          ┌───||───┐
          │ Rf=10MΩ│
          ├──/\/\──┤
RX_pad ───┤−       │          R=100Ω    C=100pF
          │  OP    ├────┤──/\/\──┬──||──┬──── ADC_IN
Vref ─────┤+       │          GND     GND
          └────────┘
```

### Feedback Components
- **Cf = 2.2 pF** (COG/C0G/NPO ceramic, 0402). Gain: Vout = Q/Cf. At 0.1 pC input → 50 mV output.
  - **Must be COG/NPO** — X7R drifts ±10–20% with temperature. COG is stable to ±30 ppm/°C.
  - Adjust empirically: if ADC saturates, increase to 4.7 pF; if signal is weak, decrease to 1 pF.
- **Rf = 10 MΩ** (0402, 1%). Sets low-frequency cutoff at 7.2 kHz (well below 200 kHz excitation).
- **Anti-alias filter**: 100 Ω + 100 pF (COG) at TIA output → f₋₃dB = 16 MHz. Costs nothing, rejects HF noise.

### Op-Amp Selection

| Part | GBW | Noise | Ib | Cost | Verdict |
|------|-----|-------|-----|------|---------|
| **AD8608** | 10 MHz | 8 nV/√Hz | 1 pA | $4.50 | **First choice.** Best noise + GBW. |
| **OPA4377** | 5.5 MHz | 7 nV/√Hz | 0.5 pA | $2.50 | **Best value.** Slightly less GBW but adequate. |
| OPA4340 | 5.5 MHz | 12 nV/√Hz | 1 pA | $4.00 | Good alternative. |
| ADA4891-4 | 240 MHz | 9.2 nV/√Hz | 1.5 pA | $3.50 | Overkill GBW — useful if excitation goes to >1 MHz later. |
| MCP6004 | 1 MHz | 28 nV/√Hz | 1 pA | $0.50 | **Avoid.** Marginal GBW, 3× worse noise. |
| LMV324 | 1 MHz | 39 nV/√Hz | 10 pA | $0.40 | **Avoid.** Noise and bias current both bad. |

**Key requirement**: CMOS input (Ib < 10 pA). BJT inputs (Ib ~ 100 nA) would create 1V DC offset across 10 MΩ Rf, saturating the amplifier.

### Power Supply
- Use FPGA 3.3V rail **filtered through a π-filter**: 10 µH inductor + 10 µF ceramic on each side. Attenuates FPGA switching noise by ~30 dB.
- Vref = Vdd/2 via 2× 10K divider bypassed with 100 nF + 10 µF.
- **Decoupling**: 100 nF (X7R, 0402) directly at each Vdd pin. 10 µF (X5R, 0805) within 5mm.

### Layout Rules
- **Solid ground plane** on layer 2. No traces on ground layer.
- Cf/Rf placed **directly adjacent** to op-amp inverting input/output pins. Loop area < 10 mm².
- TIA input traces < 5mm, with ground guard rings on both sides.
- TX drive traces **physically separated** (>5mm) from RX signal path.
- **No vias in the signal path** (each via adds ~0.5 pF to ground ≈ Cf).

---

## 4. Analog Mux

### CD4052 (Current Choice)
- Ron = ~270 Ω at 3.3V. Creates RC filter with Cin at f₋₃dB = 118 MHz. No problem at 200 kHz.
- Charge injection: ~20 pC per switch → 9V transient into Cf. **The 1 µs settling time (80 clocks) in channel_mux.v handles this** — ADC sampling waits until after settling.
- Ron mismatch between channels (±30 Ω) creates ~1% gain variation. Calibrated out by the Lissajous correction in `calibration.py`.
- **Adequate for prototype.** Cost: $0.30.

### Upgrade Path
- **ADG1604** ($3.50): Ron = 4 Ω, charge injection = 1.5 pC. 13× less charge injection → could reduce settling to ~100 ns, increasing measurement rate ~5×.
- **MAX4734** ($1.20): Ron = 2 Ω, charge injection = 2 pC. Best value upgrade.

---

## 5. ADC (AD9226)

### Reference
- **Use internal reference** for prototype. Synchronous demodulation is ratiometric — absolute reference drift cancels. Only differential reference noise matters (~60 dB SNR in 200 kHz BW, adequate).

### Clock Jitter
- FPGA GPIO jitter ~200–500 ps RMS. At 200 kHz signal: SNR_jitter = 64 dB (10.7 ENOB). Not the limiting factor.

### Layout
- **Put the ADC on the amp board** (keeps analog path short).
- 12-bit data bus + clock to FPGA via flat cable. Insert ground wires every 3–4 signals.
- Keep ADC clock trace ≥5mm from analog input traces.

---

## 6. EMI & Noise

### What Sync Demod Rejects
- All frequencies except 200 kHz (and aliases at N×3.2 MHz ± 200 kHz).
- DC offsets, 50/60 Hz mains, motor PWM harmonics — all rejected.
- The 4-phase differential measurement (sin = ch0−ch2, cos = ch1−ch3) rejects common-mode interference.

### What It Doesn't Reject
- Noise at exactly 200 kHz. Fix: change excitation freq slightly (197 kHz, 203 kHz) via `freq_div`.
- Noise at 3.0 MHz or 3.4 MHz (aliases to 200 kHz at 3.2 MHz sample rate). Fix: the TIA + RC filter attenuate these.

### Ground Loops
- **Star ground** at the amp board. Single wire from scale ground, single wire from reader ground, single connection to FPGA.
- Do NOT ground the scale to both the amp board AND the machine frame.

### Machine Noise
- Stepper motors: broadband 10 kHz–10 MHz. If step frequency is near 200 kHz, increase excitation to 500 kHz (`freq_div=160`).
- Shield reader cable and amp board if operating near VFDs or servos.

---

## 7. Mechanical

### Air Gap Sensitivity
- **Uniform gap change**: Affects amplitude equally across all phases → atan2 cancels it. No position error.
- **Non-uniform (tilt)**: 10 µm tilt end-to-end across 4-pitch reader → ~1.25 µm position shift.
- **Keep tilt <0.2°** (28 µm gap difference over 8mm reader). Use shim pads or spring-loaded reader.

### Gap Control Options
1. **Shim pads** (0.4mm shim stock on reader corners, sliding on scale surface). Simplest.
2. **Ball-bearing guide rail**. Precise but expensive.
3. **Spring-loaded flex reader** on PTFE wear strip. Commercial-grade.

### Contamination
- Non-conductive dust: negligible up to ~50 µm thick.
- Oil film: atan2 rejects amplitude changes. Negligible.
- **Metal chips: catastrophic** (shorts TX±, creates direct coupling). Keep chips off the scale.
- Water droplets: moderate effect (ε_r=80). Use hydrophobic coating if wet environment.

---

## 8. Recommended BOM

| Qty | Part | PN | Description | Cost |
|-----|------|----|-------------|------|
| 1 | Op-amp | **AD8608ARUZ** | Quad CMOS, 10 MHz GBW, TSSOP-14 | $4.50 |
| 1 | Mux | CD4052BM96 | Dual 4:1 analog, SOIC-16 | $0.40 |
| 4 | Cf | GRM1555C1H2R2CZ01D | 2.2 pF COG 0402 | $0.20 |
| 4 | Rf | RC0402FR-0710ML | 10 MΩ 1% 0402 | $0.08 |
| 2 | Vref | RC0402FR-0710KL | 10K 1% 0402 (divider) | $0.02 |
| 4 | R_filt | RC0402FR-07100RL | 100 Ω 0402 (anti-alias) | $0.04 |
| 4 | C_filt | GRM1555C1H101JA01D | 100 pF COG 0402 | $0.08 |
| 6 | C_byp | GRM155R71C104KA88D | 100 nF X7R 0402 | $0.12 |
| 3 | C_bulk | GRM21BR61C106KE15L | 10 µF X5R 0805 | $0.30 |
| 1 | L_filt | LQM21FN100M70L | 10 µH 0805 (π-filter) | $0.15 |
| 1 | NTC | NCP15XH103F03RC | 10K NTC 0402 (temp sensor) | $0.10 |
| — | Scale PCB | JLCPCB | 2L ENIG FR4 1.6mm, 200mm | ~$8 |
| — | Reader PCB | JLCPCB | 2L ENIG FR4 0.8mm | ~$3 |
| — | Amp PCB | JLCPCB | 2L FR4 1.6mm | ~$3 |

**Total: ~$20** (components + PCBs in prototype qty 5)

---

## 9. Checklist

### DO
1. 2-layer PCBs with solid ground plane on layer 2 (all 3 boards)
2. ENIG surface finish on scale and reader
3. COG/NPO capacitors for Cf (never X7R)
4. Open solder mask over electrode regions
5. Guard traces between TX+/TX- and between RX phases
6. Reader-to-amp cable <5cm
7. π-filter on analog 3.3V supply
8. 100 nF decoupling directly at op-amp power pins
9. NTC thermistor on scale for software thermal compensation
10. Verify Lissajous circularity on first power-up

### DON'T
1. OSP finish on scale (oxidizes)
2. Route signals on ground plane layer
3. X7R/Y5V for Cf
4. Run TX traces parallel to RX traces in cable
5. Ground scale to machine frame AND amp board (ground loop)
6. Single-layer scale PCB (no ground shield)
7. Cable >10cm without driven shield
8. MCP6004/LMV324 for TIA (marginal GBW, high noise)
9. ADC clock trace adjacent to analog input
10. Ignore thermal effects on scales >50mm

### VERIFY on First Prototype
- **Lissajous** (Signal tab): perfect circle = good. Ellipse = gain imbalance. Off-center = DC offset.
- **Noise floor** (Position tab, stationary): target <2 µm P2P (<4 counts)
- **Repeatability**: 10× approach-and-return, σ < 1 µm
- **Amplitude uniformity**: sweep full travel in Mode 2, check amplitude variation <30%

---

## Firmware Changes Needed

The guide identifies a few firmware-side improvements to support the hardware:

1. **`generate_electrodes.py`**: Modify to generate filled copper zones (not traces) for RX pads, add guard traces, and add solder mask openings — this is a code change.
2. **`calibration.py`**: Add NTC temperature compensation function — code change.
3. **`channel_mux.v`**: If upgrading from CD4052 to ADG1604, reduce `DEFAULT_SETTLING` from 80 to 10–20 clocks — trivial parameter change.

These are minor and can be done when the PCBs are being fabricated.
