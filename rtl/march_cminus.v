//============================================================================
// march_cminus.v
// Shared March C- MBIST controller. Tests the N_MEM memories one after
// another (one memory port active at a time, one comparator for all).
//
// March C- (10N operations per memory):
//   E0 : up/any  (w0)
//   E1 : up      (r0, w1)
//   E2 : up      (r1, w0)
//   E3 : down    (r0, w1)
//   E4 : down    (r1, w0)
//   E5 : up/any  (r0)
// Data background: solid all-0 / all-1 words.
//
// One operation is issued per cycle. The memory read is registered (1-cycle
// latency), so every read is compared one cycle later using a small pipeline
// (cmp_* registers). The test continues after a mismatch so every faulty row
// is reported, one fail per cycle at most.
//
// Detection summary for single-cell faults:
//   SA1        -> first fails on E1 (r0)
//   SA0        -> first fails on E2 (r1)
//   TF up      -> first fails on E2 (r1)
//   TF down    -> first fails on E3 (r0)
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module march_cminus #(
    parameter N_MEM  = 2,
    parameter ROWS   = 256,
    parameter WIDTH  = 8,
    // derived - passed down from the top
    parameter ADDR_W = (ROWS > 1) ? $clog2(ROWS) : 1,
    parameter MEM_W  = (N_MEM > 1) ? $clog2(N_MEM) : 1
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   start,       // 1-cycle pulse

    output wire                   busy,
    output wire                   done,        // 1-cycle pulse at the end

    // memory access request (muxed onto memory `mem_sel` by the top)
    output wire [MEM_W-1:0]       mem_sel,
    output wire [ADDR_W-1:0]      addr,
    output wire                   we,
    output wire                   re,
    output wire [WIDTH-1:0]       wdata,

    // registered read data of every memory
    input  wire [N_MEM*WIDTH-1:0] rdata_bus,

    // fail report (valid for one cycle per failing read)
    output wire                   fail_valid,
    output wire [MEM_W-1:0]       fail_mem,
    output wire [ADDR_W-1:0]      fail_row,
    output wire [WIDTH-1:0]       fail_bits,   // 1 = bit read wrong
    output wire                   fail_exp,    // expected value of the word (0/1)
    output wire [2:0]             fail_elem    // March element of the failure
);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_RUN   = 2'd1,
                     S_DRAIN = 2'd2,   // wait for the last read's compare
                     S_FIN   = 2'd3;   // assert done

    localparam [ADDR_W-1:0] A_MAX = ROWS - 1;

    reg [1:0]        state;
    reg [MEM_W-1:0]  mem_q;   // memory under test
    reg [2:0]        elem;    // March element 0..5
    reg [ADDR_W-1:0] a;       // current address
    reg              op;      // operation index within the element (0/1)

    // ------------------------------------------------------------------
    // Element decode: number of ops, direction, current op type and value
    // ------------------------------------------------------------------
    reg two_ops, down, is_rd, val;
    always @(*) begin
        two_ops = 1'b1;
        down    = 1'b0;
        is_rd   = 1'b0;
        val     = 1'b0;
        case (elem)
            3'd0: begin two_ops = 1'b0; is_rd = 1'b0; val = 1'b0; end      // w0
            3'd1: begin is_rd = ~op; val = op;           end                 // r0,w1
            3'd2: begin is_rd = ~op; val = ~op;          end                 // r1,w0
            3'd3: begin down = 1'b1; is_rd = ~op; val = op;  end             // r0,w1
            3'd4: begin down = 1'b1; is_rd = ~op; val = ~op; end             // r1,w0
            default: begin two_ops = 1'b0; is_rd = 1'b1; val = 1'b0; end   // r0
        endcase
    end

    wire last_op   = ~two_ops | op;
    wire last_addr = down ? (a == {ADDR_W{1'b0}}) : (a == A_MAX);
    wire last_elem = (elem == 3'd5);
    wire last_mem  = (mem_q == N_MEM - 1);

    // ------------------------------------------------------------------
    // Sequencer
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            mem_q <= {MEM_W{1'b0}};
            elem  <= 3'd0;
            a     <= {ADDR_W{1'b0}};
            op    <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_RUN;
                        mem_q <= {MEM_W{1'b0}};
                        elem  <= 3'd0;
                        a     <= {ADDR_W{1'b0}};
                        op    <= 1'b0;
                    end
                end

                S_RUN: begin
                    if (!last_op) begin
                        op <= 1'b1;
                    end else begin
                        op <= 1'b0;
                        if (!last_addr) begin
                            a <= down ? a - 1'b1 : a + 1'b1;
                        end else if (!last_elem) begin
                            elem <= elem + 1'b1;
                            // E3 and E4 run downwards, the rest upwards
                            a <= (elem == 3'd2 || elem == 3'd3) ? A_MAX : {ADDR_W{1'b0}};
                        end else if (!last_mem) begin
                            mem_q <= mem_q + 1'b1;
                            elem  <= 3'd0;
                            a     <= {ADDR_W{1'b0}};
                        end else begin
                            state <= S_DRAIN;
                        end
                    end
                end

                S_DRAIN: state <= S_FIN;
                default: state <= S_IDLE;   // S_FIN
            endcase
        end
    end

    assign busy = (state != S_IDLE);
    assign done = (state == S_FIN);

    // ------------------------------------------------------------------
    // Memory request
    // ------------------------------------------------------------------
    assign mem_sel = mem_q;
    assign addr    = a;
    assign we      = (state == S_RUN) & ~is_rd;
    assign re      = (state == S_RUN) &  is_rd;
    assign wdata   = {WIDTH{val}};

    // ------------------------------------------------------------------
    // Compare pipeline (read data arrives one cycle after the request)
    // ------------------------------------------------------------------
    reg              cmp_v;
    reg              cmp_exp;
    reg [MEM_W-1:0]  cmp_mem;
    reg [ADDR_W-1:0] cmp_row;
    reg [2:0]        cmp_elem;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmp_v    <= 1'b0;
            cmp_exp  <= 1'b0;
            cmp_mem  <= {MEM_W{1'b0}};
            cmp_row  <= {ADDR_W{1'b0}};
            cmp_elem <= 3'd0;
        end else begin
            cmp_v    <= (state == S_RUN) & is_rd;
            cmp_exp  <= val;
            cmp_mem  <= mem_q;
            cmp_row  <= a;
            cmp_elem <= elem;
        end
    end

    wire [WIDTH-1:0] rsel = rdata_bus[cmp_mem*WIDTH +: WIDTH];

    assign fail_bits  = rsel ^ {WIDTH{cmp_exp}};
    assign fail_valid = cmp_v & (|fail_bits);
    assign fail_mem   = cmp_mem;
    assign fail_row   = cmp_row;
    assign fail_exp   = cmp_exp;
    assign fail_elem  = cmp_elem;

endmodule

`default_nettype wire
