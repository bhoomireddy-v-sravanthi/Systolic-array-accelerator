# =============================================================================
# Makefile -- systolic-array-accelerator
#
# Simulation targets use the open-source Icarus Verilog simulator (iverilog/
# vvp) -- no license required, works out of the box on any machine with
# iverilog installed (`apt install iverilog` / `brew install icarus-verilog`).
#
# Synthesis targets call Vivado in batch (non-project) mode. You need Vivado
# installed and `vivado` on your PATH. Edit PART below to match your target
# FPGA before running `make synth`.
# =============================================================================

RTL_SRC   := rtl/src/pe.sv rtl/src/systolic_array.sv rtl/src/axi_lite_systolic_wrapper.sv
XDC       := rtl/constraints/constraints.xdc
PART      ?= xc7a100tcsg324-1
TOP       ?= systolic_array
ARRAY_SIZE ?= 4

.PHONY: sim sim-all sim-pe sim-axi synth clean

## Run the systolic_array testbench at a single ARRAY_SIZE (default 4).
## Usage: make sim ARRAY_SIZE=8
sim:
	iverilog -g2012 -DTB_ARRAY_SIZE=$(ARRAY_SIZE) -o sim_array.vvp \
		rtl/src/pe.sv rtl/src/systolic_array.sv tb/tb_systolic_array.sv
	vvp sim_array.vvp

## Sweep every thesis-validated tile size (1x1 via tb_pe, then 2..10 via the
## generic array testbench) and print a consolidated pass/fail summary.
sim-all: sim-pe
	@for n in 2 3 5 10; do \
		echo "===== ARRAY_SIZE=$$n ====="; \
		iverilog -g2012 -DTB_ARRAY_SIZE=$$n -o sim_$$n.vvp \
			rtl/src/pe.sv rtl/src/systolic_array.sv tb/tb_systolic_array.sv; \
		vvp sim_$$n.vvp; \
	done

## 1x1 case: verified directly against the PE module (see tb/tb_pe.sv for why).
sim-pe:
	iverilog -g2012 -o sim_pe.vvp rtl/src/pe.sv tb/tb_pe.sv
	vvp sim_pe.vvp

## AXI4-Lite wrapper testbench (drives the real bus protocol end to end).
sim-axi:
	iverilog -g2012 -o sim_axi.vvp $(RTL_SRC) tb/tb_axi_wrapper.sv
	vvp sim_axi.vvp

## Vivado non-project-mode synthesis + implementation + reports.
## Produces results/synth_report.txt and results/utilization_report.txt.
## Requires Vivado on PATH; edit PART for your target device.
synth:
	vivado -mode batch -source scripts/synth.tcl \
		-tclargs $(PART) $(TOP) $(ARRAY_SIZE)

clean:
	rm -f *.vvp sim_*.vvp
	rm -rf vivado_project *.jou *.log .Xil
