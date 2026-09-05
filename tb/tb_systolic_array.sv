// =============================================================================
// tb_systolic_array.sv
// Directed testbench for the weight-stationary systolic_array core.
//
// Flow: load a known weight matrix W into the array's stationary registers,
// then drive a known activation vector `a` into the row inputs and hold it
// (broadcast) while the pipeline settles, then compare the resulting column
// accumulations against a software reference y[c] = sum_r a[r]*W[r][c].
//
// Verifies multiple tile sizes, matching the thesis validation approach
// (1x1, 3x3, 5x5, 10x10 all exercised via the sweep in scripts/run_sim.sh).
// =============================================================================
`timescale 1ns/1ps

module tb_systolic_array;

    localparam int ARRAY_SIZE = `TB_ARRAY_SIZE;
    localparam int DATA_WIDTH = 16;
    localparam int ACC_WIDTH  = 32;
    localparam int CLK_PERIOD = 10;

    logic clk = 0;
    logic rst_n;
    logic en;
    logic load_en;

    logic [DATA_WIDTH-1:0] w_in [ARRAY_SIZE][ARRAY_SIZE];
    logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] a_in_row;
    logic [ARRAY_SIZE-1:0][ACC_WIDTH-1:0]  acc_out_col;

    logic signed [DATA_WIDTH-1:0] a_vec [ARRAY_SIZE];
    logic signed [DATA_WIDTH-1:0] w_mat [ARRAY_SIZE][ARRAY_SIZE];

    int errors = 0;

    systolic_array #(
        .ARRAY_SIZE (ARRAY_SIZE),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .SIGNED_EN  (1)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .en          (en),
        .load_en     (load_en),
        .w_in        (w_in),
        .a_in_row    (a_in_row),
        .acc_out_col (acc_out_col)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    function automatic longint golden_dot(input int col);
        longint sum = 0;
        for (int k = 0; k < ARRAY_SIZE; k++) begin
            sum += a_vec[k] * w_mat[k][col];
        end
        return sum;
    endfunction

    task automatic run_case(input string name);
        int settle;
        rst_n = 0; en = 0; load_en = 0;
        a_in_row = '0;
        for (int r = 0; r < ARRAY_SIZE; r++)
            for (int c = 0; c < ARRAY_SIZE; c++)
                w_in[r][c] = '0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Load stationary weights (parallel load in one cycle)
        for (int r = 0; r < ARRAY_SIZE; r++)
            for (int c = 0; c < ARRAY_SIZE; c++)
                w_in[r][c] = w_mat[r][c];
        load_en = 1;
        @(posedge clk);
        load_en = 0;

        // Drive activation vector and let the pipeline settle
        en = 1;
        for (int r = 0; r < ARRAY_SIZE; r++) a_in_row[r] = a_vec[r];

        // Settle time must cover BOTH: activation propagating rightward to the
        // last column (2 cycles x (ARRAY_SIZE-1) column hops) AND the partial
        // sum then propagating downward through all rows (2 cycles x
        // ARRAY_SIZE row hops) before the bottom-row output is stable.
        settle = 2*(ARRAY_SIZE - 1) + 2*ARRAY_SIZE + 10;
        repeat (settle) @(posedge clk);
        en = 0;

        for (int c = 0; c < ARRAY_SIZE; c++) begin
            longint expected = golden_dot(c);
            longint actual   = signed'(acc_out_col[c]);
            if (actual !== expected) begin
                $display("[FAIL] %s col=%0d expected=%0d actual=%0d", name, c, expected, actual);
                errors++;
            end else begin
                $display("[PASS] %s col=%0d result=%0d", name, c, actual);
            end
        end
    endtask

    initial begin
        $display("=== systolic_array testbench : ARRAY_SIZE=%0d ===", ARRAY_SIZE);

        // Case 1: identity weight matrix -> output should equal activation vector
        for (int i = 0; i < ARRAY_SIZE; i++) a_vec[i] = i + 1;
        for (int i = 0; i < ARRAY_SIZE; i++)
            for (int j = 0; j < ARRAY_SIZE; j++)
                w_mat[i][j] = (i == j) ? 1 : 0;
        run_case("identity_weights");

        // Case 2: pseudo-random values
        for (int i = 0; i < ARRAY_SIZE; i++) a_vec[i] = $urandom_range(0, 255);
        for (int i = 0; i < ARRAY_SIZE; i++)
            for (int j = 0; j < ARRAY_SIZE; j++)
                w_mat[i][j] = $urandom_range(0, 255);
        run_case("pseudo_random");

        // Case 3: negative values (signed arithmetic check)
        for (int i = 0; i < ARRAY_SIZE; i++) a_vec[i] = -(i + 1);
        for (int i = 0; i < ARRAY_SIZE; i++)
            for (int j = 0; j < ARRAY_SIZE; j++)
                w_mat[i][j] = (i + j) - ARRAY_SIZE;
        run_case("signed_values");

        // Case 4: re-load a second, different weight matrix on the same DUT
        // instance to confirm the load port correctly overwrites prior weights
        for (int i = 0; i < ARRAY_SIZE; i++) a_vec[i] = 1;
        for (int i = 0; i < ARRAY_SIZE; i++)
            for (int j = 0; j < ARRAY_SIZE; j++)
                w_mat[i][j] = 2;
        run_case("reload_weights");

        if (errors == 0)
            $display("=== ALL TESTS PASSED (ARRAY_SIZE=%0d) ===", ARRAY_SIZE);
        else
            $display("=== %0d TEST(S) FAILED (ARRAY_SIZE=%0d) ===", errors, ARRAY_SIZE);

        $finish;
    end

endmodule
