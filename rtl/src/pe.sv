// =============================================================================
// File        : pe.sv
// Module      : pe (Processing Element)
// Description : Weight-stationary, two-stage pipelined Multiply-Accumulate
//               (MAC) unit -- the basic building block of the systolic array.
//
//               Each PE holds ONE weight value locally in a stationary
//               register, loaded once via `load_en` + `w_in`. During compute,
//               activations stream left-to-right across the row (a_in -> a_out,
//               pipeline-delayed, unchanged in value) and partial sums stream
//               top-to-bottom down the column (acc_in -> acc_out), each PE
//               adding its own a*w term into the running sum.
//
//               Weight-stationary was chosen (over streaming weights through
//               the column) because it is the standard, provably-correct
//               systolic GEMM structure -- the same output-accumulation
//               pattern used in e.g. Google's TPU MXU -- and keeps each PE's
//               local storage and control minimal. See docs/architecture.md
//               for the verification methodology and design trade-offs.
//
//               Explicit if-else (rather than ternary) is used for the signed/
//               unsigned select to keep the design portable across synthesis
//               toolchains (Yosys / Vivado).
// =============================================================================

module pe #(
    parameter int DATA_WIDTH = 16,   // operand bit width
    parameter int ACC_WIDTH  = 32,   // accumulator bit width
    parameter bit SIGNED_EN  = 1     // 1 = signed arithmetic, 0 = unsigned
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   en,        // pipeline enable / stall

    // Weight load (stationary) port
    input  logic                   load_en,   // pulse: capture w_in into local register
    input  logic [DATA_WIDTH-1:0]  w_in,

    // Activation input (from left neighbor), partial-sum input (from top neighbor)
    input  logic [DATA_WIDTH-1:0]  a_in,
    input  logic [ACC_WIDTH-1:0]   acc_in,

    // Activation output (to right neighbor), partial-sum output (to bottom neighbor)
    output logic [DATA_WIDTH-1:0]  a_out,
    output logic [ACC_WIDTH-1:0]   acc_out
);

    // ---------------------------------------------------------------
    // Stationary weight register
    // ---------------------------------------------------------------
    logic [DATA_WIDTH-1:0] w_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_reg <= '0;
        end else if (load_en) begin
            w_reg <= w_in;
        end
    end

    // ---------------------------------------------------------------
    // Stage 1 : Multiply (activation x stationary weight)
    // ---------------------------------------------------------------
    logic [DATA_WIDTH-1:0]   a_s1;
    logic [2*DATA_WIDTH-1:0] mult_s1;
    logic [ACC_WIDTH-1:0]    acc_s1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_s1    <= '0;
            mult_s1 <= '0;
            acc_s1  <= '0;
        end else if (en) begin
            a_s1   <= a_in;
            acc_s1 <= acc_in;

            if (SIGNED_EN) begin
                mult_s1 <= $signed(a_in) * $signed(w_reg);
            end else begin
                mult_s1 <= a_in * w_reg;
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage 2 : Accumulate
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out   <= '0;
            acc_out <= '0;
        end else if (en) begin
            a_out <= a_s1; // pass activation through to the next column, pipeline-aligned

            if (SIGNED_EN) begin
                acc_out <= $signed(acc_s1) + $signed({{(ACC_WIDTH-2*DATA_WIDTH){mult_s1[2*DATA_WIDTH-1]}}, mult_s1});
            end else begin
                acc_out <= acc_s1 + {{(ACC_WIDTH-2*DATA_WIDTH){1'b0}}, mult_s1};
            end
        end
    end

endmodule
