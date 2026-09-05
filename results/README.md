# Results

## Simulation (verified, real)

`sim_logs/simulation_results.txt` is the actual console output from running
this repo's testbenches with Icarus Verilog (`make sim-pe`, `make sim
ARRAY_SIZE=N` for N in {2,3,5,10}, `make sim-axi`). 98 checks, 0 failures,
covering:

- The processing element in isolation (also stands in for the `ARRAY_SIZE=1`
  case — see `tb/tb_pe.sv` for why)
- The systolic array core at `ARRAY_SIZE` = 2, 3, 5, 10 (identity-weight,
  pseudo-random, signed-value, and weight-reload test cases)
- The AXI4-Lite wrapper, driven through its real bus protocol end to end
  (weight load -> activation write -> start -> poll -> read)

Reproduce with: `make sim-pe && make sim-all && make sim-axi`

## Synthesis (run this yourself for real numbers)

This section is intentionally **not** filled in with numbers, because doing
so without actually running synthesis would mean fabricating results. Run:

```
make synth PART=<your_target_part> TOP=systolic_array ARRAY_SIZE=<N>
```

(edit `PART` in the Makefile or pass it on the command line — see
`rtl/constraints/constraints.xdc` for a pin-constraint template you'll need
to fill in for your board first).

This produces, in this directory:
- `utilization_report.txt` — LUT / FF / DSP / BRAM usage
- `synth_report.txt` — timing summary / achieved Fmax
- `power_report.txt` — estimated power

Once you've run it, paste the real LUT/FF/DSP and Fmax numbers into the
table below (suggested: run at ARRAY_SIZE = 4 and ARRAY_SIZE = 8 to show the
throughput/resource tradeoff called out in the CV bullet).

| ARRAY_SIZE | LUTs | FFs | DSPs | Fmax (MHz) |
|---|---|---|---|---|
| 4 | _run `make synth`_ | | | |
| 8 | _run `make synth`_ | | | |
