# Makefile — Cap-Scale capacitive linear encoder FPGA build flow
# Target: Colorlight i9 v7.2 (ECP5 LFE5U-45F-6BG381C)
# Toolchain: yosys → nextpnr-ecp5 → ecppack → openFPGALoader

PROJ     = top
PACKAGE  = CABGA381
SPEED    = 6
LPF      = constraints/colorlight_i9.lpf
SRC      = $(wildcard src/*.v)

.PHONY: all clean prog prog-sram test-all \
	sim_excitation sim_sync_demod sim_position_calc sim_channel_mux \
	sim_cmd_parser sim_top

all: $(PROJ).bit

# Synthesis
$(PROJ).json: $(SRC)
	yosys -p "synth_ecp5 -top top -json $@" $(SRC)

# Place & Route
$(PROJ).config: $(PROJ).json $(LPF)
	nextpnr-ecp5 --45k --package $(PACKAGE) --speed $(SPEED) \
		--json $< --lpf $(LPF) --textcfg $@ --lpf-allow-unconstrained

# Bitstream generation
$(PROJ).bit: $(PROJ).config
	ecppack --compress --input $< --bit $@

# Flash to Colorlight i9 via JTAG
prog: $(PROJ).bit
	openFPGALoader -b colorlight-i9 $<

# Program to SRAM (volatile, faster for development)
prog-sram: $(PROJ).bit
	openFPGALoader -b colorlight-i9 --write-sram $<

# Simulation (iverilog + vvp)
# Uses testbench/pll_sim.v instead of src/pll.v (EHXPLLL not available in iverilog)
SIM_SRC = $(filter-out src/pll.v,$(SRC))

sim_excitation:
	iverilog -g2012 -o testbench/tb_excitation_gen.vvp -I src \
		src/excitation_gen.v testbench/tb_excitation_gen.v
	cd testbench && vvp tb_excitation_gen.vvp

sim_sync_demod:
	iverilog -g2012 -o testbench/tb_sync_demod.vvp -I src \
		src/sync_demod.v testbench/tb_sync_demod.v
	cd testbench && vvp tb_sync_demod.vvp

sim_position_calc:
	iverilog -g2012 -o testbench/tb_position_calc.vvp -I src \
		src/position_calc.v testbench/tb_position_calc.v
	cd testbench && vvp tb_position_calc.vvp

sim_channel_mux:
	iverilog -g2012 -o testbench/tb_channel_mux.vvp -I src \
		src/channel_mux.v testbench/tb_channel_mux.v
	cd testbench && vvp tb_channel_mux.vvp

sim_cmd_parser:
	iverilog -g2012 -o testbench/tb_cmd_parser.vvp -I src \
		src/cmd_parser.v testbench/tb_cmd_parser.v
	cd testbench && vvp tb_cmd_parser.vvp

sim_top:
	iverilog -g2012 -o testbench/tb_top.vvp -I src \
		testbench/pll_sim.v $(SIM_SRC) testbench/tb_top.v
	cd testbench && vvp tb_top.vvp

# Run all simulation targets and report results
test-all:
	@echo "=========================================="
	@echo "  Running all testbenches"
	@echo "=========================================="
	@pass=0; fail=0; \
	for target in sim_excitation sim_sync_demod sim_position_calc \
		sim_channel_mux sim_cmd_parser sim_top; do \
		echo ""; \
		echo "--- Running $$target ---"; \
		if $(MAKE) $$target; then \
			echo ">>> $$target: OK"; \
			pass=$$((pass + 1)); \
		else \
			echo ">>> $$target: FAIL"; \
			fail=$$((fail + 1)); \
		fi; \
	done; \
	echo ""; \
	echo "=========================================="; \
	echo "  Results: $$pass passed, $$fail failed"; \
	echo "=========================================="; \
	if [ $$fail -ne 0 ]; then exit 1; fi

clean:
	rm -f $(PROJ).json $(PROJ).config $(PROJ).bit
	rm -f testbench/*.vvp testbench/*.vcd

# Utilization report
util: $(PROJ).json
	@echo "=== Resource Utilization ==="
	@yosys -p "synth_ecp5 -top top -noflatten" $(SRC) 2>&1 | \
		grep -E "LUT|DFF|BRAM|DP16KD|CCU2|MULT" || true
