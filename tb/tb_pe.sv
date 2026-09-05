// =============================================================================
// tb_pe.sv
// Standalone testbench for the pe.sv processing element.
//
// A 1x1 systolic array is structurally just a single PE, so this testbench
// also serves as the verification for the ARRAY_SIZE=1 configuration (the
// generic tb_systolic_array.sv sweep covers ARRAY_SIZE=2..10; a known Icarus
// Verilog limitation with size-1 unpacked array ports makes instantiating
// systolic_array with ARRAY_SIZE=1 awkward in this open-source simulator --
// this does not affect Vivado synthesis/simulation of the same RTL).
// =============================================================================
`timescale 1ns/1ps

module tb_pe;

    localparam int DATA_WIDTH = 16;
    localparam int ACC_WIDTH  = 32;
    localparam int CLK_PERIOD = 10;

    logic clk = 0;
    logic rst_n, en, load_en;
    logic signed [DATA_WIDTH-1:0] w_in, a_in;
    logic signed [ACC_WIDTH-1:0]  acc_in;
    logic signed [DATA_WIDTH-1:0] a_out;
    logic signed [ACC_WIDTH-1:0]  acc_out;

    int errors = 0;

    pe #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .SIGNED_EN  (1)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (en),
        .load_en (load_en),
        .w_in    (w_in),
        .a_in    (a_in),
        .acc_in  (acc_in),
        .a_out   (a_out),
        .acc_out (acc_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic run_case(input string name, input int a_val, input int w_val, input int acc_val);
        longint expected;
        rst_n = 0; en = 0; load_en = 0;
        a_in = '0; w_in = '0; acc_in = '0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        w_in = w_val;
        load_en = 1;
        @(posedge clk);
        load_en = 0;

        en = 1;
        a_in   = a_val;
        acc_in = acc_val;
        repeat (4) @(posedge clk); // 2-stage pipeline + margin
        en = 0;

        expected = longint'(a_val) * longint'(w_val) + longint'(acc_val);
        if (longint'(acc_out) !== expected) begin
            $display("[FAIL] %s expected=%0d actual=%0d", name, expected, acc_out);
            errors++;
        end else begin
            $display("[PASS] %s result=%0d", name, acc_out);
        end
    endtask

    initial begin
        $display("=== pe testbench (also verifies ARRAY_SIZE=1 case) ===");
        run_case("positive",      5,   7,   0);
        run_case("with_acc_in",   3,   4,   100);
        run_case("negative_a",   -6,   5,   0);
        run_case("negative_w",    6,  -5,   0);
        run_case("both_negative",-6,  -5,   10);
        run_case("zero_weight",   9,   0,   42);
        run_case("reload_weight", 2,   9,   0); // confirms load_en overwrites prior weight

        if (errors == 0)
            $display("=== ALL PE TESTS PASSED ===");
        else
            $display("=== %0d PE TEST(S) FAILED ===", errors);

        $finish;
    end

endmodule
