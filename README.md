# Cap-Scale: Capacitive PCB Linear Encoder

Open-source capacitive linear encoder using an FPGA for synchronous demodulation and atan2 position calculation. Achieves sub-micron resolution from sinusoidal PCB electrodes.

## Architecture

```
Scale PCB (TX+/TX- sinusoidal electrodes)
    ↕ capacitive coupling
Reader PCB (4-phase RX pads: 0°, 90°, 180°, 270°)
    ↓ analog signals
Amp Board (CD4052 mux + trans-impedance amp)
    ↓ single-ended analog
AD9226 (12-bit ADC, synchronous sampling)
    ↓ parallel data bus
Colorlight i9 FPGA (ECP5 LFE5U-45F)
    ├─ Excitation generator (200 kHz square wave)
    ├─ 4-channel synchronous demodulator
    ├─ atan2 position calculator (2D BRAM LUT)
    └─ UART + SPI output
    ↓
Host PC (Cap-Scale Inspector GUI)
```

## Hardware

| Component | Part | Notes |
|-----------|------|-------|
| FPGA board | Colorlight i9 v7.2 | ECP5 LFE5U-45F, 108 EBR blocks |
| ADC | AD9226 breakout | 12-bit, 65 MSPS |
| Analog mux | CD4052 | 4:1 analog multiplexer |
| Op-amp | AD8608 or OPA4340 | Quad, rail-to-rail, low noise |
| Scale PCB | Custom | Sinusoidal copper electrodes, 2mm pitch |
| Reader PCB | Custom | 4-phase sense pads |

### Pin Mapping (Colorlight i9 J2/J3)

| Signal | Pin | FPGA Site | Reused From |
|--------|-----|-----------|-------------|
| TX_POS | J2_B1 | M4 | FM_PIN |
| TX_NEG | J2_A | L4 | SH_PIN |
| MUX_SEL[0] | J2_B_CTRL | K5 | ICG_PIN |
| MUX_SEL[1] | J3_B0 | C1 | FLASH_0 |
| ADC_CLK | J2_G1 | N3 | — |
| ADC_D[11:0] | J1+J2 | various | — |
| UART_TX | J3_R0 | D1 | — |
| UART_RX | J3_G0 | E2 | — |

## Building

### FPGA

Requires [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (yosys, nextpnr-ecp5, ecppack, iverilog).

```bash
# Generate atan2 LUT
python scripts/gen_atan2_lut.py

# Synthesize + place & route + bitstream
make

# Run all testbenches
make test-all

# Flash to FPGA
make prog
```

**Utilization**: 1613 LUTs (3%), 3 DP16KD EBR blocks (2%).

### Host Application

Requires Python 3.10+ and [uv](https://docs.astral.sh/uv/).

```bash
cd host
uv sync
uv run python -m cap_inspector.app

# Run tests
uv run pytest -v
```

## FPGA Modules

| Module | Description |
|--------|-------------|
| `excitation_gen` | 200 kHz square-wave TX drive, configurable frequency |
| `adc_capture` | Latches AD9226 parallel data on sample strobe |
| `sync_demod` | 4-channel multiply-accumulate demodulator (20-bit accumulators) |
| `channel_mux` | CD4052 sequential mux controller with settling delay |
| `position_calc` | atan2 via 64×64 BRAM LUT + pitch counting (4096 counts/pitch) |
| `position_tx` | UART packet serializer (6B position / 20B diagnostics) |
| `cmd_parser` | EX/MD/ZR command parser over UART |
| `spi_peripheral` | RP2040 register-mapped SPI interface |
| `pll` | 25 MHz → 80 MHz via ECP5 EHXPLLL |
| `uart_tx/rx` | 921600 baud, 8N1 |

## Host GUI Tabs

| Tab | Function |
|-----|----------|
| **Position** | Large DRO readout (48pt), 10s strip chart, min/max/P2P stats |
| **Signal** | Lissajous plot (sin vs cos), per-channel amplitude bars, offset/imbalance/phase metrics |
| **Vibration** | FFT magnitude plot, peak frequency, RMS displacement |
| **Runout** | Polar plot, TIR readout, synchronous/asynchronous error |
| **Calibration** | Signal sweep, sin/cos correction table, known-length calibration |
| **Settings** | Excitation frequency, averaging, mode, pitch, CSV logging |

## Protocol

### Commands (Host → FPGA)
- `EX` (4B): `'E' 'X'` + freq_div[2B BE] — set excitation frequency
- `MD` (4B): `'M' 'D'` + mode[1B] + avg[1B] — set output mode and averaging
- `ZR` (2B): `'Z' 'R'` — zero position

### Responses (FPGA → Host)
- **Mode 1** (6B): `0xAA 0x55` + position[4B LE signed]
- **Mode 2** (20B): `0xAA 0x55` + position[4B] + sin[2B] + cos[2B] + amplitude[2B] + ch0-3[8B]

## PCB Electrode Generator

```bash
python pcb/generate_electrodes.py --pitch 2.0 --length 100 --finger-length 5
```

Generates sinusoidal KiCad footprints for TX+/TX- scale electrodes and 4-phase reader pads.

## License

MIT
