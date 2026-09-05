// =============================================================================
// File        : systolic_array.sv
// Module      : systolic_array
// Description : Configurable N x N weight-stationary systolic array, built
//               from pe.sv processing elements connected in a nearest-neighbor
//               mesh.
//
//               Weights W[r][c] are loaded once (parallel load, gated by
//               load_en) into each PE's local stationary register.
//               Activations then stream left -> right across each row.
//               Partial sums flow top -> bottom down each column and are
//               read out at the bottom row, giving:
//
//                   y[c] = sum_r  a[r] * W[r][c]     (vector-matrix product)
//
//               i.e. for an activation vector `a` (length ARRAY_SIZE) and a
//               stationary weight matrix W (ARRAY_SIZE x ARRAY_SIZE), the
//               array computes y = a^T * W. Streaming successive activation
//               vectors through row 0..ARRAY_SIZE-1 with the correct skew
//               extends this to a full matrix-matrix product (see
//               docs/architecture.md).
//
//               ARRAY_SIZE is parameterizable across a validated range of 1x1
//               to 10x10, matching the reconfigurable-overlay design goal: a
//               single RTL description re-instantiable at any tile dimension
//               without structural changes.
// =============================================================================

module systolic_array #(
    parameter int ARRAY_SIZE = 4,    // N x N tile, 1 <= ARRAY_SIZE <= 10 (validated range)
    parameter int DATA_WIDTH = 16,
    parameter int ACC_WIDTH  = 32,
    parameter bit SIGNED_EN  = 1
) (
    input  logic                                              clk,
    input  logic                                              rst_n,
    input  logic                                              en,

    // Weight load port: parallel-load the full stationary weight matrix
    // (unpacked 2D array port: w_in[row][col], each element DATA_WIDTH wide)
    input  logic                                              load_en,
    input  logic [DATA_WIDTH-1:0]                             w_in [ARRAY_SIZE][ARRAY_SIZE],

    // Row inputs: activations fed into the left edge of each row (packed 2D vector)
    input  logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0]             a_in_row,

    // Column outputs: accumulated partial sums read from the bottom edge (packed 2D vector)
    output logic [ARRAY_SIZE-1:0][ACC_WIDTH-1:0]              acc_out_col
);

    // Internal mesh wires: [row][col] indexing
    // a_wire[r][c]   = activation flowing INTO pe(r,c) from the left
    // acc_wire[r][c] = partial sum flowing INTO pe(r,c) from the top
    logic [DATA_WIDTH-1:0] a_wire   [ARRAY_SIZE][ARRAY_SIZE+1];
    logic [ACC_WIDTH-1:0]  acc_wire [ARRAY_SIZE+1][ARRAY_SIZE];

    genvar r, c;
    generate
        // Tie array edge inputs
        for (r = 0; r < ARRAY_SIZE; r++) begin : g_row_in
            assign a_wire[r][0] = a_in_row[r];
        end
        for (c = 0; c < ARRAY_SIZE; c++) begin : g_col_in
            assign acc_wire[0][c] = '0;  // fresh accumulation at the top of each column
        end

        // Instantiate the PE mesh
        for (r = 0; r < ARRAY_SIZE; r++) begin : g_pe_row
            for (c = 0; c < ARRAY_SIZE; c++) begin : g_pe_col
                pe #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .ACC_WIDTH  (ACC_WIDTH),
                    .SIGNED_EN  (SIGNED_EN)
                ) u_pe (
                    .clk     (clk),
                    .rst_n   (rst_n),
                    .en      (en),
                    .load_en (load_en),
                    .w_in    (w_in[r][c]),
                    .a_in    (a_wire[r][c]),
                    .acc_in  (acc_wire[r][c]),
                    .a_out   (a_wire[r][c+1]),
                    .acc_out (acc_wire[r+1][c])
                );
            end
        end

        // Tie array edge outputs (bottom row accumulation result per column)
        for (c = 0; c < ARRAY_SIZE; c++) begin : g_col_out
            assign acc_out_col[c] = acc_wire[ARRAY_SIZE][c];
        end
    endgenerate

endmodule
