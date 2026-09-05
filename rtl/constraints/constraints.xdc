## =============================================================================
## constraints.xdc
## Generic timing constraints for the systolic-array accelerator.
##
## Pin (LOC/IOSTANDARD) constraints are board-specific and intentionally left
## as placeholders -- fill these in for your target board (e.g. Digilent
## Arty A7-100T / Nexys A7) before running implementation. Timing constraints
## (clock period, false paths) apply generally.
## =============================================================================

# ---------------------------------------------------------------------------
# Clock
# ---------------------------------------------------------------------------
# Adjust to your target clock frequency. 100 MHz (10.000 ns) is a common
# starting point for AMD/Xilinx Artix-7 class parts; tighten once you have
# real timing closure numbers from Vivado (see results/README.md).
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk]

# ---------------------------------------------------------------------------
# Reset (asynchronous active-low) -- treat as a false path for setup/hold,
# but keep recovery/removal checks (default Vivado behavior for set_false_path
# is fine here since rst_n only gates synchronous logic behavior, not data).
# ---------------------------------------------------------------------------
set_false_path -from [get_ports rst_n]

# ---------------------------------------------------------------------------
# Example pin constraints (Digilent Arty A7-100T) -- UNCOMMENT and edit for
# your actual board's pin assignments before running synthesis/implementation.
# ---------------------------------------------------------------------------
# set_property PACKAGE_PIN E3   [get_ports clk]
# set_property IOSTANDARD LVCMOS33 [get_ports clk]
#
# set_property PACKAGE_PIN C2   [get_ports rst_n]
# set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
