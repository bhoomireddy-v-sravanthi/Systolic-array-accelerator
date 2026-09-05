# AXI4-Lite Register Map

`axi_lite_systolic_wrapper` exposes a 32-bit, word-addressed AXI4-Lite
control/data interface. `N` = `ARRAY_SIZE` below.

| Address | Name | Access | Description |
|---|---|---|---|
| `0x000` | `CONTROL` | W | `[0]` start (self-clearing pulse), `[1]` soft_reset, `[2]` load_weights (self-clearing pulse) |
| `0x004` | `STATUS` | R | `[0]` busy, `[1]` done |
| `0x008` | `ARRAY_SIZE` | R | Read-only, equals the `ARRAY_SIZE` parameter |
| `0x100 + 4*i` | `A_IN[i]` | W | Activation input for row `i`, `i = 0 .. N-1` |
| `0x200 + 4*(N*r + c)` | `W_IN[r][c]` | W | Weight input, row `r` / column `c`, `r,c = 0 .. N-1` |
| `0x300 + 4*i` | `ACC_OUT[i]` | R | Result for output column `i`, valid when `STATUS.done = 1` |

## Control flow

1. Write the full weight matrix: `N*N` writes to `W_IN[r][c]` at
   `0x200 + 4*(N*r + c)`.
2. Pulse `CONTROL.load_weights` (write `0x4` to `0x000`) — captures the
   weight matrix into each PE's stationary register in one cycle.
3. Write the activation vector: `N` writes to `A_IN[i]` at `0x100 + 4*i`.
4. Pulse `CONTROL.start` (write `0x1` to `0x000`).
5. Poll `STATUS` (`0x004`) until bit `[1]` (`done`) is set.
6. Read the result vector from `ACC_OUT[i]` at `0x300 + 4*i`.

This sequence is exercised end-to-end (including the real AXI handshake, not
just the datapath) in `tb/tb_axi_wrapper.sv` — see
`results/sim_logs/simulation_results.txt` for the passing run.

## Notes

- `DATA_WIDTH`-wide operands are zero/sign-extended into the 32-bit AXI
  word on write; `ACC_WIDTH`-wide results are sign-extended on read.
- This is a single-shot (load -> start -> poll -> read) control scheme,
  representative of a simple memory-mapped accelerator. It is not a
  streaming AXI4-Stream datapath.
- `CONTROL.soft_reset` (bit 1) holds the systolic array core in reset
  without resetting the AXI4-Lite bus logic itself.
