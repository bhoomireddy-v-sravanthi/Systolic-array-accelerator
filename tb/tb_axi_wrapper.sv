// =============================================================================
// tb_axi_wrapper.sv
// Testbench for axi_lite_systolic_wrapper. Drives the DUT through its real
// AXI4-Lite interface (write weights -> pulse load -> write activations ->
// pulse start -> poll status -> read results) using simple blocking BFM
// tasks, and checks results against a software golden model.
// =============================================================================
`timescale 1ns/1ps

module tb_axi_wrapper;

    localparam int ARRAY_SIZE = 4;
    localparam int DATA_WIDTH = 16;
    localparam int ACC_WIDTH  = 32;
    localparam int AXI_DATA_W = 32;
    localparam int CLK_PERIOD = 10;

    logic clk = 0;
    logic rst_n;

    logic [11:0]  s_axi_awaddr;
    logic         s_axi_awvalid, s_axi_awready;
    logic [31:0]  s_axi_wdata;
    logic [3:0]   s_axi_wstrb;
    logic         s_axi_wvalid, s_axi_wready;
    logic [1:0]   s_axi_bresp;
    logic         s_axi_bvalid, s_axi_bready;
    logic [11:0]  s_axi_araddr;
    logic         s_axi_arvalid, s_axi_arready;
    logic [31:0]  s_axi_rdata;
    logic [1:0]   s_axi_rresp;
    logic         s_axi_rvalid, s_axi_rready;

    int errors = 0;

    axi_lite_systolic_wrapper #(
        .ARRAY_SIZE (ARRAY_SIZE),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH)
    ) dut (
        .clk (clk), .rst_n (rst_n),
        .s_axi_awaddr (s_axi_awaddr), .s_axi_awvalid (s_axi_awvalid), .s_axi_awready (s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),  .s_axi_wstrb (s_axi_wstrb), .s_axi_wvalid (s_axi_wvalid), .s_axi_wready (s_axi_wready),
        .s_axi_bresp  (s_axi_bresp),  .s_axi_bvalid (s_axi_bvalid), .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr), .s_axi_arvalid (s_axi_arvalid), .s_axi_arready (s_axi_arready),
        .s_axi_rdata  (s_axi_rdata),  .s_axi_rresp (s_axi_rresp), .s_axi_rvalid (s_axi_rvalid), .s_axi_rready (s_axi_rready)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // ---------------- Simple AXI4-Lite BFM tasks ----------------
    task automatic axi_write(input logic [11:0] addr, input logic [31:0] data);
        @(posedge clk);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= 4'hF;
        s_axi_wvalid  <= 1;
        s_axi_bready  <= 1;

        // AW and W channels may complete on different cycles; wait for each
        // independently using level-sensitive `wait`, sampled just after the
        // clock edge that accepts them.
        fork
            begin
                wait (s_axi_awvalid && s_axi_awready);
                @(posedge clk);
                s_axi_awvalid <= 0;
            end
            begin
                wait (s_axi_wvalid && s_axi_wready);
                @(posedge clk);
                s_axi_wvalid <= 0;
            end
        join

        wait (s_axi_bvalid);
        @(posedge clk);
        s_axi_bready <= 0;
        @(posedge clk);
    endtask

    task automatic axi_read(input logic [11:0] addr, output logic [31:0] data);
        @(posedge clk);
        s_axi_araddr  <= addr;
        s_axi_arvalid <= 1;
        s_axi_rready  <= 1;

        wait (s_axi_arvalid && s_axi_arready);
        @(posedge clk);
        s_axi_arvalid <= 0;

        wait (s_axi_rvalid);
        data = s_axi_rdata;
        @(posedge clk);
        s_axi_rready <= 0;
        @(posedge clk);
    endtask

    // ---------------- Golden model ----------------
    logic signed [DATA_WIDTH-1:0] a_vec [ARRAY_SIZE];
    logic signed [DATA_WIDTH-1:0] w_mat [ARRAY_SIZE][ARRAY_SIZE];

    function automatic longint golden_dot(input int col);
        longint sum;
        sum = 0;
        for (int k = 0; k < ARRAY_SIZE; k++) begin
            sum = sum + (longint'(a_vec[k]) * longint'(w_mat[k][col]));
        end
        return sum;
    endfunction

    initial begin
        logic [31:0] rdata;
        logic [31:0] status;
        int poll_count;

        rst_n = 0; s_axi_awvalid=0; s_axi_wvalid=0; s_axi_bready=0;
        s_axi_arvalid=0; s_axi_rready=0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("=== AXI4-Lite systolic wrapper testbench (ARRAY_SIZE=%0d) ===", ARRAY_SIZE);

        // Stimulus: small distinct matrix
        for (int i = 0; i < ARRAY_SIZE; i++) a_vec[i] = i + 2;
        for (int i = 0; i < ARRAY_SIZE; i++)
            for (int j = 0; j < ARRAY_SIZE; j++)
                w_mat[i][j] = (i == j) ? (j + 1) : 0; // diagonal weight matrix

        // 1) Write weight matrix
        for (int r = 0; r < ARRAY_SIZE; r++)
            for (int c = 0; c < ARRAY_SIZE; c++)
                axi_write(12'h200 + ((r*ARRAY_SIZE + c) << 2), w_mat[r][c]);

        // 2) Pulse load_weights (CONTROL bit 2)
        axi_write(12'h000, 32'h4);

        // 3) Write activation vector
        for (int i = 0; i < ARRAY_SIZE; i++)
            axi_write(12'h100 + (i << 2), a_vec[i]);

        // 4) Pulse start (CONTROL bit 0)
        axi_write(12'h000, 32'h1);

        // 5) Poll STATUS.done
        poll_count = 0;
        do begin
            axi_read(12'h004, status);
            poll_count++;
        end while (!status[1] && poll_count < 200);

        if (!status[1]) begin
            $display("[FAIL] STATUS.done never asserted after %0d polls", poll_count);
            errors++;
        end else begin
            $display("[INFO] done asserted after %0d poll reads", poll_count);
        end

        // 6) Read back results and check
        for (int c = 0; c < ARRAY_SIZE; c++) begin
            longint expected;
            expected = golden_dot(c);
            axi_read(12'h300 + (c << 2), rdata);
            if ($signed(rdata) !== expected) begin
                $display("[FAIL] col=%0d expected=%0d actual=%0d", c, expected, $signed(rdata));
                errors++;
            end else begin
                $display("[PASS] col=%0d result=%0d", c, $signed(rdata));
            end
        end

        // 7) Sanity check ARRAY_SIZE readback register
        axi_read(12'h008, rdata);
        if (rdata !== ARRAY_SIZE) begin
            $display("[FAIL] ARRAY_SIZE register mismatch: expected=%0d actual=%0d", ARRAY_SIZE, rdata);
            errors++;
        end else begin
            $display("[PASS] ARRAY_SIZE register readback = %0d", rdata);
        end

        if (errors == 0)
            $display("=== ALL AXI WRAPPER TESTS PASSED ===");
        else
            $display("=== %0d AXI WRAPPER TEST(S) FAILED ===", errors);

        $finish;
    end

endmodule
