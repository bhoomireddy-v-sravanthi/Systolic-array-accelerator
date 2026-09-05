// =============================================================================
// File        : axi_lite_systolic_wrapper.sv
// Module      : axi_lite_systolic_wrapper
// Description : AXI4-Lite memory-mapped control/data wrapper around the
//               systolic_array core, enabling direct integration into an
//               FPGA/SoC memory-mapped system (e.g. behind a Zynq PS-PL AXI
//               interconnect).
//
// Register Map (word-addressed, 32-bit AXI4-Lite) -- see docs/register_map.md
// for the full table:
//   0x000  CONTROL    [0]=start (self-clearing pulse), [1]=soft_reset,
//                      [2]=load_weights (self-clearing pulse)
//   0x004  STATUS     [0]=busy, [1]=done
//   0x008  ARRAY_SIZE (read-only, = ARRAY_SIZE param)
//   0x100 + 4*i        A_IN[i]     activation input for row i    (i = 0..N-1)
//   0x200 + 4*(N*r+c)  W_IN[r][c]  weight input, row r / col c   (r,c = 0..N-1)
//   0x300 + 4*i        ACC_OUT[i]  result for column i, read-only, valid when
//                                  STATUS.done = 1
//
// Notes:
//   - DATA_WIDTH operands are zero/sign-extended into 32-bit AXI words.
//   - ACC_WIDTH results are sign-extended to 32 bits on read (ACC_WIDTH is
//     expected <= 32 for this wrapper; asserted below).
//   - Control flow: write weight registers -> pulse CONTROL.load_weights ->
//     write activation registers -> pulse CONTROL.start -> poll
//     STATUS.done -> read ACC_OUT[i]. Representative of a simple
//     memory-mapped accelerator, not a full streaming AXI4-Stream datapath.
// =============================================================================

module axi_lite_systolic_wrapper #(
    parameter int ARRAY_SIZE  = 4,
    parameter int DATA_WIDTH  = 16,
    parameter int ACC_WIDTH   = 32,
    parameter bit SIGNED_EN   = 1,
    parameter int AXI_ADDR_W  = 12,
    parameter int AXI_DATA_W  = 32
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // AXI4-Lite Write Address channel
    input  logic [AXI_ADDR_W-1:0]     s_axi_awaddr,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    // AXI4-Lite Write Data channel
    input  logic [AXI_DATA_W-1:0]     s_axi_wdata,
    input  logic [(AXI_DATA_W/8)-1:0] s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,

    // AXI4-Lite Write Response channel
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    // AXI4-Lite Read Address channel
    input  logic [AXI_ADDR_W-1:0]     s_axi_araddr,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    // AXI4-Lite Read Data channel
    output logic [AXI_DATA_W-1:0]     s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready
);

    initial begin
        assert (ACC_WIDTH <= AXI_DATA_W)
            else $fatal(1, "ACC_WIDTH must be <= AXI_DATA_W for axi_lite_systolic_wrapper");
    end

    // ---------------------------------------------------------------
    // Local register file
    // ---------------------------------------------------------------
    logic [DATA_WIDTH-1:0] a_regs   [ARRAY_SIZE];
    logic [DATA_WIDTH-1:0] w_regs   [ARRAY_SIZE][ARRAY_SIZE];
    logic [ACC_WIDTH-1:0]  acc_regs [ARRAY_SIZE];

    logic core_en, core_load_en, soft_reset;
    logic start_pulse, load_pulse;
    logic busy, done;

    // Address-decode scratch signals (module-scope: declaring these inline
    // inside always_ff with an initializer is non-portable -- some simulators
    // treat it as a one-time static initializer rather than a per-cycle
    // combinational value; see docs/architecture.md for the debugging note).
    logic [15:0] idx;
    logic [15:0] flat_idx;
    logic [15:0] rr, cc;
    logic [15:0] rd_idx;

    localparam int PIPE_LATENCY = 2*(ARRAY_SIZE-1) + 2*ARRAY_SIZE + 4;
    logic [$clog2(PIPE_LATENCY+2)-1:0] latency_cnt;

    logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] a_in_row;
    logic [ARRAY_SIZE-1:0][ACC_WIDTH-1:0]  acc_out_col;

    always_comb begin
        for (int i = 0; i < ARRAY_SIZE; i++) a_in_row[i] = a_regs[i];
    end

    systolic_array #(
        .ARRAY_SIZE (ARRAY_SIZE),
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .SIGNED_EN  (SIGNED_EN)
    ) u_core (
        .clk         (clk),
        .rst_n       (rst_n & ~soft_reset),
        .en          (core_en),
        .load_en     (core_load_en),
        .w_in        (w_regs),
        .a_in_row    (a_in_row),
        .acc_out_col (acc_out_col)
    );

    // ---------------------------------------------------------------
    // Control FSM
    // ---------------------------------------------------------------
    typedef enum logic [1:0] {IDLE, LOAD, RUN, DONE} state_t;
    state_t state;

    assign core_en      = (state == RUN);
    assign core_load_en = (state == LOAD);
    assign busy         = (state == RUN) || (state == LOAD);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            latency_cnt <= '0;
            done        <= 1'b0;
            for (int i = 0; i < ARRAY_SIZE; i++) acc_regs[i] <= '0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (load_pulse) begin
                        state <= LOAD;
                    end else if (start_pulse) begin
                        state       <= RUN;
                        latency_cnt <= '0;
                    end
                end
                LOAD: begin
                    // single-cycle parallel load, matches u_core's load_en pulse
                    state <= IDLE;
                end
                RUN: begin
                    if (latency_cnt == PIPE_LATENCY[$bits(latency_cnt)-1:0]) begin
                        for (int i = 0; i < ARRAY_SIZE; i++) acc_regs[i] <= acc_out_col[i];
                        state <= DONE;
                        done  <= 1'b1;
                    end else begin
                        latency_cnt <= latency_cnt + 1'b1;
                    end
                end
                DONE: begin
                    if (load_pulse) begin
                        state <= LOAD;
                        done  <= 1'b0;
                    end else if (start_pulse) begin
                        state       <= RUN;
                        latency_cnt <= '0;
                        done        <= 1'b0;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // AXI4-Lite Write channel (simple 2-phase handshake, one outstanding txn)
    // ---------------------------------------------------------------
    logic [AXI_ADDR_W-1:0] awaddr_latched;
    logic aw_hs, w_hs;

    assign s_axi_awready = !s_axi_bvalid && !aw_hs;
    assign s_axi_wready  = !s_axi_bvalid && !w_hs;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_hs          <= 1'b0;
            w_hs           <= 1'b0;
            awaddr_latched <= '0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= 2'b00;
            soft_reset     <= 1'b0;
            start_pulse    <= 1'b0;
            load_pulse     <= 1'b0;
            for (int i = 0; i < ARRAY_SIZE; i++) a_regs[i] <= '0;
            for (int r = 0; r < ARRAY_SIZE; r++)
                for (int c = 0; c < ARRAY_SIZE; c++) w_regs[r][c] <= '0;
        end else begin
            start_pulse <= 1'b0; // self-clearing
            load_pulse  <= 1'b0; // self-clearing

            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_latched <= s_axi_awaddr;
                aw_hs          <= 1'b1;
            end

            if (s_axi_wvalid && s_axi_wready) begin
                w_hs <= 1'b1;
            end

            if (aw_hs && w_hs && !s_axi_bvalid) begin
                if (awaddr_latched == 12'h000) begin
                    start_pulse <= s_axi_wdata[0];
                    soft_reset  <= s_axi_wdata[1];
                    load_pulse  <= s_axi_wdata[2];
                end else if (awaddr_latched[11:8] == 4'h1) begin
                    idx = awaddr_latched[7:2];
                    if (idx < ARRAY_SIZE) a_regs[idx] <= s_axi_wdata[DATA_WIDTH-1:0];
                end else if (awaddr_latched[11:9] == 3'h1) begin
                    // 0x200 - 0x3FF reserved for weight matrix (N*N words)
                    flat_idx = (awaddr_latched - 12'h200) >> 2;
                    rr = flat_idx / ARRAY_SIZE;
                    cc = flat_idx % ARRAY_SIZE;
                    if (rr < ARRAY_SIZE && cc < ARRAY_SIZE)
                        w_regs[rr][cc] <= s_axi_wdata[DATA_WIDTH-1:0];
                end
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY
                aw_hs        <= 1'b0;
                w_hs         <= 1'b0;
            end

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------
    // AXI4-Lite Read channel
    // ---------------------------------------------------------------
    logic [AXI_ADDR_W-1:0] araddr_latched;
    logic ar_hs;

    assign s_axi_arready = !s_axi_rvalid && !ar_hs;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_hs          <= 1'b0;
            araddr_latched <= '0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rdata    <= '0;
            s_axi_rresp    <= 2'b00;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                araddr_latched <= s_axi_araddr;
                ar_hs          <= 1'b1;
            end

            if (ar_hs && !s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                if (araddr_latched == 12'h000) begin
                    s_axi_rdata <= '0;
                end else if (araddr_latched == 12'h004) begin
                    s_axi_rdata <= {30'b0, done, busy};
                end else if (araddr_latched == 12'h008) begin
                    s_axi_rdata <= ARRAY_SIZE[AXI_DATA_W-1:0];
                end else if (araddr_latched[11:8] == 4'h3) begin
                    rd_idx = (araddr_latched - 12'h300) >> 2;
                    if (rd_idx < ARRAY_SIZE)
                        s_axi_rdata <= {{(AXI_DATA_W-ACC_WIDTH){acc_regs[rd_idx][ACC_WIDTH-1]}}, acc_regs[rd_idx]};
                    else
                        s_axi_rdata <= '0;
                end else begin
                    s_axi_rdata <= '0;
                end
                ar_hs <= 1'b0;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
