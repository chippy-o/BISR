//============================================================================
// dedicated_bisr_top.v
// BASELINE ARCHITECTURE: conventional dedicated BISR.
//
// Every SRAM gets its own complete BISR (control FSM, March C- MBIST, fault
// logger, BIRA, repair table, remap) and only its own local spares - there is
// no global pool. It is built from the same blocks as the proposed design
// (shared_bisr_top with N_MEM = 1, N_GLOBAL = 0), so area / repair
// comparisons are like-for-like.
//
//   N_LOCAL = 1 : "dedicated" baseline
//   N_LOCAL = 2 : "equal total spares" baseline (same spare count as
//                 1 local + 2 global shared between 2 SRAMs)
//
// Ports match shared_bisr_top so the same testbench drives both.
// Status outputs are combined across the N instances.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module dedicated_bisr_top #(
    parameter N_MEM        = 2,
    parameter ROWS         = 256,
    parameter WIDTH        = 8,
    parameter N_LOCAL      = 1,
    parameter FT_DEPTH     = 8,
    parameter SPARE_GATING = 1,
    // derived - do not override
    parameter ADDR_W = (ROWS > 1) ? $clog2(ROWS) : 1,
    parameter LCNT_W = $clog2(N_LOCAL + 1)
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      scan_en,

    input  wire                      bisr_start,
    output wire                      bisr_busy,        // any instance busy
    output wire                      bisr_done,        // all instances done
    output wire                      bisr_pass,        // all instances passed
    output wire                      bisr_unrepairable,
    output wire                      bisr_overflow,
    output wire                      bisr_verify_fail,
    output reg  [15:0]               bisr_fault_count, // sum over instances
    output wire [N_MEM*LCNT_W-1:0]   bisr_local_used,
    output wire [7:0]                bisr_global_used, // always 0 (no pool)

    input  wire [N_MEM*ADDR_W-1:0]   func_addr,
    input  wire [N_MEM-1:0]          func_we,
    input  wire [N_MEM-1:0]          func_re,
    input  wire [N_MEM*WIDTH-1:0]    func_wdata,
    output wire [N_MEM*WIDTH-1:0]    func_rdata
);

    wire [N_MEM-1:0]    i_busy, i_done, i_pass, i_unrep, i_ovf, i_vfail;
    wire [N_MEM*16-1:0] i_fcnt;

    genvar g;
    generate
        for (g = 0; g < N_MEM; g = g + 1) begin : g_inst
            shared_bisr_top #(
                .N_MEM        (1),
                .ROWS         (ROWS),
                .WIDTH        (WIDTH),
                .N_LOCAL      (N_LOCAL),
                .N_GLOBAL     (0),
                .FT_DEPTH     (FT_DEPTH),
                .SPARE_GATING (SPARE_GATING)
            ) u_bisr (
                .clk               (clk),
                .rst_n             (rst_n),
                .scan_en           (scan_en),
                .bisr_start        (bisr_start),
                .bisr_busy         (i_busy[g]),
                .bisr_done         (i_done[g]),
                .bisr_pass         (i_pass[g]),
                .bisr_unrepairable (i_unrep[g]),
                .bisr_overflow     (i_ovf[g]),
                .bisr_verify_fail  (i_vfail[g]),
                .bisr_fault_count  (i_fcnt[g*16 +: 16]),
                .bisr_local_used   (bisr_local_used[g*LCNT_W +: LCNT_W]),
                .bisr_global_used  (),
                .func_addr         (func_addr [g*ADDR_W +: ADDR_W]),
                .func_we           (func_we[g]),
                .func_re           (func_re[g]),
                .func_wdata        (func_wdata[g*WIDTH +: WIDTH]),
                .func_rdata        (func_rdata[g*WIDTH +: WIDTH])
            );
        end
    endgenerate

    // Combined status
    assign bisr_busy         = |i_busy;
    assign bisr_done         = &i_done;
    assign bisr_pass         = &i_pass;
    assign bisr_unrepairable = |i_unrep;
    assign bisr_overflow     = |i_ovf;
    assign bisr_verify_fail  = |i_vfail;
    assign bisr_global_used  = 8'd0;

    integer m;
    always @(*) begin
        bisr_fault_count = 16'd0;
        for (m = 0; m < N_MEM; m = m + 1)
            bisr_fault_count = bisr_fault_count + i_fcnt[m*16 +: 16];
    end

endmodule

`default_nettype wire
