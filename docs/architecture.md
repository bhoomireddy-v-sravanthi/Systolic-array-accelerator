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
RTL, with the datapath, control scheme, and a from-scratch verification
suite built out to industry standard.

---

# Part 1 — Design

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
actually built.

**AXI4-Lite vs. AXI4-Stream.** AXI4-Lite was chosen for the control/data
interface because the accelerator's usage pattern (load weights once, run
repeated activation passes, poll for completion) maps naturally onto a
register-level interface. A streaming AXI4-Stream front end would be the
natural next step for continuous, back-pressure-driven activation feeds —
noted under Future Work below.

**Parallel vs. serial weight load.** Weights load into all `ARRAY_SIZE^2`
PEs in a single cycle via a wide load port, keeping load latency constant
regardless of matrix size at the cost of pin/fan-in growth at larger array
sizes. A serial (systolic) load chain would trade load latency for a
narrower load interface — noted under Future Work.

---

# Part 2 — Design Verification

## Test plan

| Level | Testbench | Cases | Why these cases |
|---|---|---|---|
| Unit (PE) | `tb/tb_pe.sv` | Positive operands, accumulator carry-in, negative activation, negative weight, both operands negative, zero weight, weight reload | Isolates the MAC datapath and the stationary-weight register from array-level timing, so a failure here points straight at the PE rather than the mesh. Also stands in for the `ARRAY_SIZE=1` array configuration (structurally a single PE). |
| Array | `tb/tb_systolic_array.sv` | Identity weight matrix, pseudo-random operands, signed values, weight reload — swept across `ARRAY_SIZE` = 2, 3, 5, 10 | Identity isolates pure pass-through correctness; pseudo-random exercises the full MAC/accumulate path without a predictable structure to mask errors; signed values specifically target the sign-extension logic in the accumulator; weight reload confirms the stationary register is genuinely overwritable, not just write-once. |
| Integration | `tb/tb_axi_wrapper.sv` | Full register-level control sequence (weight write → load pulse → activation write → start → status poll → result read) driven through the real AXI4-Lite protocol | A datapath-only bench can pass while the bus-facing register/FSM logic is still broken — this level exists specifically to catch that class of bug (see below). |

Every check is self-checking against a behavioral golden model computed
independently in the testbench (not against expected values hand-copied
from the DUT), so a regression can be re-run and re-verified without manual
inspection. All three levels run via `make sim-pe`, `make sim-all`, and
`make sim-axi`, with output captured in
`results/sim_logs/simulation_results.txt` — 98 checks, 0 failures, as of
the current RTL.

## Bugs found and root-caused during verification

**Weight-propagation limitation (array level).** The earliest version of
the array held both operands constant and sampled the output after the
pipeline settled. It failed for every `ARRAY_SIZE > 1`, tracing back to the
streaming-weight datapath described in Part 1 — a value that only
pipelines downward unchanged cannot carry a distinct weight per row within
one compute pass. Caught by the array-level golden-model comparison,
root-caused by tracing the wire-level dataflow, fixed by moving to a
stationary per-PE weight register.

**Address re-latch on the AXI read channel (integration level).** The read
channel's `ARREADY` was combinationally driven from `!RVALID` only, without
also gating on "address already latched" the way the write channel's
`AWREADY`/`WREADY` do. This let the address register re-latch on a
subsequent cycle while a transaction was still in flight. Caught because
the integration-level bench drives the real bus protocol rather than
forcing internal signals directly.

**Simulator static-lifetime pitfall (portability).** A scratch index
variable declared with an inline initializer directly inside a clocked
(`always_ff`) block — e.g. `int idx = addr[7:2];` written in that position —
is treated by some simulators (Icarus Verilog among them) as having
*static* lifetime, so the initializer runs once at time zero instead of
once per clock edge. This produced a wrapper that always returned the
address decoded on its very first transaction, regardless of what was
requested afterward. The fix, and the pattern followed throughout this
repo: declare such scratch signals once at module scope and assign — never
initialize — them inside the clocked block.

## Future work

- AXI4-Stream front end for continuous activation feeds without a
  load/start/poll cycle per pass
- Serial (systolic) weight-load chain to reduce load-port fan-in beyond
  10x10
- INT8 / mixed-precision datapath variant for higher-density inference
  workloads
- Constrained-random stimulus and functional coverage on top of the
  current directed test plan, for larger array sizes where exhaustive
  directed cases become impractical

## Module summary

| Module | File | Role |
|---|---|---|
| `pe` | `rtl/src/pe.sv` | Weight-stationary 2-stage pipelined MAC processing element |
| `systolic_array` | `rtl/src/systolic_array.sv` | Parameterizable N x N mesh of `pe` instances |
| `axi_lite_systolic_wrapper` | `rtl/src/axi_lite_systolic_wrapper.sv` | AXI4-Lite register/control wrapper for FPGA/SoC integration |
