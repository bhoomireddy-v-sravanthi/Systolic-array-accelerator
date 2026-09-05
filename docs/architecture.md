# Architecture & Design Notes

## Overview

This accelerator implements a parameterizable **weight-stationary systolic
array** for matrix multiplication on FPGA. It computes:

```
y[c] = sum_r  a[r] * W[r][c]        (per activation vector)
```

i.e. a vector-matrix product `y = a^T * W`, where `a` is a length-N
activation vector and `W` is an N x N weight matrix held stationary in the
array. Streaming successive activation vectors through row 0 with the
correct skew extends this to a full M x N x N matrix-matrix product.

The design originates from my M.Tech thesis, *"Design and Implementation of
a Reconfigurable Systolic Array Overlay on OpenFPGA for Scalable AI
Inference,"* which established the parameterizable mesh structure
(`ARRAY_SIZE` 1x1–10x10) and the two-stage pipelined MAC processing element.
This repo carries that structure forward into synthesizable, AXI-integrated
RTL, with the datapath and control scheme refined for correctness and
generality as described below.

## Processing element

Each PE is a two-stage pipeline:

- **Stage 1** — multiply the incoming activation against the PE's locally
  stored weight
- **Stage 2** — add the product to the partial sum arriving from the PE
  above, forward the result down, and pass the activation through to the
  PE on the right

Weights are **stationary**: loaded once per PE via a `load_en` pulse and
held for the duration of a compute pass. This is the standard, well-proven
systolic GEMM structure (the same output-accumulation approach used in
production accelerators such as Google's TPU MXU) and keeps per-PE control
minimal — no re-streaming or timing skew is needed for the weight operand,
only for the activation stream in the full matrix-matrix case.

## Array-level integration

`systolic_array` instantiates an N x N mesh of `pe` blocks with nearest-
neighbor connectivity: weights parallel-load into every PE in one cycle,
activations flow left-to-right across rows, and partial sums flow top-to-
bottom down columns. `ARRAY_SIZE` is a single parameter — the RTL is
re-instantiable at any tile dimension from 1x1 to 10x10 without structural
changes, which was the core reconfigurability goal carried over from the
original overlay design.

`axi_lite_systolic_wrapper` sits on top and exposes the array as a memory-
mapped AXI4-Lite peripheral — register-level control for weight/activation
load, start/status handshaking, and result readback — so the core can drop
into a Zynq PS-PL system or behind any AXI4-Lite host. See
[docs/register_map.md](register_map.md) for the full register map and
control sequence.

## Design decisions & trade-offs

**Weight-stationary vs. streaming weights.** An early iteration of the
datapath streamed the weight operand through each column on every cycle
(mirroring how the activation operand flows through the row). Verification
surfaced a real limitation with that approach: a value that only pipelines
downward unchanged cannot represent a distinct weight per row within the
same compute pass — every PE in a column would end up seeing the same
value. Moving to a stationary local weight register per PE resolves this
cleanly and matches how production weight-stationary systolic arrays are
actually built; it was the right call architecturally, not just a
patch-up. This is documented here because it's a useful data point on the
design space, not because it needs to be hidden — spotting and correcting
a dataflow limitation before tape-out (or before an interviewer asks about
it) is exactly the kind of thing verification is for.

**AXI4-Lite vs. AXI4-Stream.** AXI4-Lite was chosen for the control/data
interface because the accelerator's usage pattern (load weights once, run
repeated activation passes, poll for completion) maps naturally onto a
register-level interface. A streaming AXI4-Stream front end would be the
natural next step for continuous, back-pressure-driven activation feeds —
noted under Future Work below.

## Verification methodology

- **Unit level** (`tb_pe.sv`): directed cases covering positive/negative
  operands, zero-weight, accumulator carry-in, and weight-reload — this
  testbench also stands in for the `ARRAY_SIZE=1` array configuration,
  since a 1x1 array is structurally a single PE.
- **Array level** (`tb_systolic_array.sv`): a parameterized sweep over
  `ARRAY_SIZE` = 2, 3, 5, 10, each run against identity-weight,
  pseudo-random, signed-value, and weight-reload cases, checked against a
  behavioral golden model computed independently in the testbench.
- **Integration level** (`tb_axi_wrapper.sv`): drives the design through
  its real AXI4-Lite bus protocol — write, handshake, poll, read — not just
  the underlying datapath, catching integration-level bugs a datapath-only
  testbench would miss (one such bug, an address-channel handshake
  omission, was caught this way — see below).
- All of the above run via `make sim-pe`, `make sim-all`, and `make
  sim-axi`; results are logged to `results/sim_logs/simulation_results.txt`
  rather than only asserted in text.

**A verification-tooling note worth keeping in mind for portability**: a
scratch index variable declared with an inline initializer directly inside
a clocked (`always_ff`) block — e.g. `int idx = addr[7:2];` written in that
position — is treated by some simulators (Icarus Verilog among them) as
having *static* lifetime, meaning the initializer runs once at time zero
rather than once per clock edge. This surfaced during AXI wrapper bring-up
as a wrapper that always returned the address decoded on its very first
transaction. The fix, and the general pattern followed throughout this
repo, is to declare such scratch signals once at module scope and assign
(not initialize) them inside the clocked block.

## Future work

- AXI4-Stream front end for continuous activation feeds without a
  load/start/poll cycle per pass
- Extension beyond 10x10 with a systolic weight-load chain (serial rather
  than fully parallel load) to reduce load-port fan-in at larger sizes
- INT8 / mixed-precision datapath variant for higher-density inference
  workloads

## Module summary

| Module | File | Role |
|---|---|---|
| `pe` | `rtl/src/pe.sv` | Weight-stationary 2-stage pipelined MAC processing element |
| `systolic_array` | `rtl/src/systolic_array.sv` | Parameterizable N x N mesh of `pe` instances |
| `axi_lite_systolic_wrapper` | `rtl/src/axi_lite_systolic_wrapper.sv` | AXI4-Lite register/control wrapper for FPGA/SoC integration |
