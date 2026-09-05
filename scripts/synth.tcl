# =============================================================================
# scripts/synth.tcl
# Non-project-mode Vivado batch flow: read RTL + constraints, synthesize,
# implement, and write out real utilization/timing reports.
#
# Usage:
#   vivado -mode batch -source scripts/synth.tcl -tclargs <part> <top> <array_size>
# or simply:
#   make synth PART=xc7a100tcsg324-1 TOP=systolic_array ARRAY_SIZE=8
#
# Fill in results/README.md with the numbers this produces -- do not hand-copy
# numbers from elsewhere; run this and use your own output.
# =============================================================================

set part       [lindex $argv 0]
set top        [lindex $argv 1]
set array_size [lindex $argv 2]

puts "==> Synthesizing $top for part $part (ARRAY_SIZE=$array_size)"

read_verilog -sv {rtl/src/pe.sv rtl/src/systolic_array.sv rtl/src/axi_lite_systolic_wrapper.sv}
read_xdc rtl/constraints/constraints.xdc

synth_design -top $top -part $part -generic ARRAY_SIZE=$array_size

opt_design
place_design
route_design

file mkdir results

report_utilization -file results/utilization_report.txt
report_timing_summary -file results/synth_report.txt
report_power -file results/power_report.txt

write_checkpoint -force results/${top}_${array_size}.dcp

puts "==> Done. See results/utilization_report.txt, results/synth_report.txt"
