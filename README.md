# Systolic-Array Matrix Multiplication Accelerator

Designed and implemented a systolic-array-based matrix multiplication
accelerator in RTL, targeting FPGA platforms for AI acceleration workloads.
Architected a scalable, configurable systolic array datapath, balancing
throughput against FPGA resource utilization. Integrated an AXI4-Lite memory
interface for FPGA/SoC deployment and validated the design through RTL
simulation and a Vivado synthesis flow.

This project builds on my M.Tech thesis work on a reconfigurable systolic
array overlay, extended here into a fully synthesizable, AXI-integrated
accelerator with a  verification suite.

## Highlights

- **Configurable datapath** — `ARRAY_SIZE` parameterizable 1x1 to 10x10,
  `DATA_WIDTH`/`ACC_WIDTH` parameterizable, signed or unsigned arithmetic —
  a single RTL description re-instantiable at any tile dimension without
  structural changes
- **Weight-stationary systolic architecture** — the same output-accumulation
  scheme used in production accelerators (e.g. Google's TPU MXU): weights
  load once into each PE's local register, activations stream through,
  partial sums accumulate down each column
- **AXI4-Lite integration** — memory-mapped control/data interface, ready to
  sit behind a Zynq PS-PL interconnect or any AXI4-Lite host
- **Verification** — 98 passing simulation checks across the PE, the
  full array-size sweep, and the AXI wrapper's real bus protocol, with logs
  committed to the repo 
- **Reproducible synthesis flow** — a `make synth` Vivado batch script that
  generates real utilization/timing/power reports for any target part

## Architecture

```
Activation vector a[0..N-1] ---> [PE(0,0)]--[PE(0,1)]--...--[PE(0,N-1)]
                                     |            |               |
                              [PE(1,0)]--[PE(1,1)]--...--[PE(1,N-1)]
                                     |            |               |
                                    ...          ...             ...
                                     |            |               |
                              [PE(N-1,0)]-[PE(N-1,1)]-...-[PE(N-1,N-1)]
                                     |            |               |
                                   y[0]         y[1]  ...       y[N-1]
```

Weights load once into each PE's stationary register; activations stream
left-to-right across each row; partial sums accumulate top-to-bottom down
each column. Full design rationale, trade-offs, and verification methodology
are in **[docs/architecture.md](docs/architecture.md)**.

## Repo structure

```
rtl/
  src/          Synthesizable RTL (pe.sv, systolic_array.sv, axi_lite_systolic_wrapper.sv)
  constraints/  XDC timing constraints template
tb/             Testbenches (tb_pe.sv, tb_systolic_array.sv, tb_axi_wrapper.sv)
scripts/        Vivado batch-mode synthesis script
docs/           Architecture & design-decisions writeup, AXI4-Lite register map
results/        Simulation logs; synthesis reports (generated via make synth)
```

## How to run

**Simulation** (Icarus Verilog — open-source, no license required):

```
make sim-pe                  # PE testbench (also covers the 1x1 array case)
make sim ARRAY_SIZE=8        # systolic array at one size
make sim-all                 # full sweep: 1, 2, 3, 5, 10
make sim-axi                 # AXI4-Lite wrapper, real bus protocol
```

**Synthesis** (Vivado):

```
make synth PART=xc7a100tcsg324-1 TOP=systolic_array ARRAY_SIZE=8
```

Edit `rtl/constraints/constraints.xdc` with target board pin assignments
first. See [`results/README.md`](results/README.md) for what this produces.

## Configurable features

| Parameter | Default | Description |
|---|---|---|
| `ARRAY_SIZE` | 4 | Systolic tile dimension, N x N (1–10 validated) |
| `DATA_WIDTH` | 16 | Operand bit width |
| `ACC_WIDTH` | 32 | Accumulator bit width |
| `SIGNED_EN` | 1 | Signed (1) or unsigned (0) arithmetic |

## Results

[`results/sim_logs/simulation_results.txt`](results/sim_logs/simulation_results.txt)
— real, reproducible simulation output (98 checks, 0 failures).
[`results/README.md`](results/README.md) — synthesis/utilization flow; run
`make synth` for LUT/FF/DSP/Fmax numbers on your target part.

## License

MIT — see [LICENSE](LICENSE).
