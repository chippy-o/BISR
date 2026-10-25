//============================================================================
// clustered_bisr_top.v
// SHARED BISR - top level used for any number of SRAMs.
//
// The SRAMs are split into groups ("clusters") of CLUSTER SRAMs. Each group
// is served by ONE shared_bisr_top: one control FSM, one March C- MBIST, one
// fault logger, one BIRA, one repair table, one remap unit, and a global pool
// of N_GLOBAL spare rows that any SRAM of the group can borrow. Each SRAM
// also has N_LOCAL local spare rows of its own.
//
//   N_MEM = 8, CLUSTER = 4:
//     SRAM0..SRAM3 -- shared controller 0 -- global pool 0
//     SRAM4..SRAM7 -- shared controller 1 -- global pool 1
//
// Why groups: the remap unit compares every SRAM address with every global
// spare slot (N_MEM * N_GLOBAL comparators per controller). With the pool
// growing with the number of SRAMs, one controller for many SRAMs grows as
// N^2. Capping the group size keeps the total linear in N.
//
//   CLUSTER = N_MEM                 -> one shared controller for all SRAMs
//   CLUSTER = 1, N_GLOBAL = 0       -> same as dedicated_bisr_top
//
// Groups run their BISR in parallel, so test time depends on CLUSTER, not
// on N_MEM. Ports match shared_bisr_top and dedicated_bisr_top; SRAM m is
// SRAM (m % CLUSTER) of group (m / CLUSTER). Status outputs are combined
// over all groups (pass = every group passed).
//
// N_MEM must be a multiple of CLUSTER.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module clustered_bisr_top #(
    parameter N_MEM        = 8,
    parameter CLUSTER      = 4,                         // SRAMs per controller
    parameter ROWS         = 256,
    parameter WIDTH        = 8,
    parameter N_LOCAL      = 1,
    parameter N_GLOBAL     = CLUSTER,                   // global spares PER CLUSTER
    parameter FT_DEPTH     = CLUSTER*N_LOCAL + N_GLOBAL, // per cluster (= its spares)
    parameter SPARE_GATING = 1,
    // derived - do not override
    parameter ADDR_W = (ROWS > 1) ? $clog2(ROWS) : 1,
    parameter LCNT_W = $clog2(N_LOCAL + 1),
    parameter N_CL   = N_MEM / CLUSTER
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      scan_en,

    input  wire                      bisr_start,
    output wire                      bisr_busy,        // any cluster busy
    output wire                      bisr_done,        // all clusters done
    output wire                      bisr_pass,        // all clusters passed
    output wire                      bisr_unrepairable,
    output wire                      bisr_overflow,
    output wire                      bisr_verify_fail,
    output reg  [15:0]               bisr_fault_count, // sum over clusters
    output wire [N_MEM*LCNT_W-1:0]   bisr_local_used,
    output reg  [7:0]                bisr_global_used, // sum over clusters

    input  wire [N_MEM*ADDR_W-1:0]   func_addr,
    input  wire [N_MEM-1:0]          func_we,
    input  wire [N_MEM-1:0]          func_re,
    input  wire [N_MEM*WIDTH-1:0]    func_wdata,
    output wire [N_MEM*WIDTH-1:0]    func_rdata
);

    wire [N_CL-1:0]    c_busy, c_done, c_pass, c_unrep, c_ovf, c_vfail;
    wire [N_CL*16-1:0] c_fcnt;
    wire [N_CL*8-1:0]  c_gused;

    genvar c;
    generate
        // Elaboration-time parameter check
        if (N_MEM % CLUSTER != 0) begin : g_param_error
            N_MEM_must_be_a_multiple_of_CLUSTER u_param_error ();
        end

        for (c = 0; c < N_CL; c = c + 1) begin : g_cl
            shared_bisr_top #(
                .N_MEM        (CLUSTER),
                .ROWS         (ROWS),
                .WIDTH        (WIDTH),
                .N_LOCAL      (N_LOCAL),
                .N_GLOBAL     (N_GLOBAL),
                .FT_DEPTH     (FT_DEPTH),
                .SPARE_GATING (SPARE_GATING)
            ) u_bisr (
                .clk               (clk),
                .rst_n             (rst_n),
                .scan_en           (scan_en),
                .bisr_start        (bisr_start),
                .bisr_busy         (c_busy[c]),
                .bisr_done         (c_done[c]),
                .bisr_pass         (c_pass[c]),
                .bisr_unrepairable (c_unrep[c]),
                .bisr_overflow     (c_ovf[c]),
                .bisr_verify_fail  (c_vfail[c]),
                .bisr_fault_count  (c_fcnt[c*16 +: 16]),
                .bisr_local_used   (bisr_local_used[c*CLUSTER*LCNT_W +: CLUSTER*LCNT_W]),
                .bisr_global_used  (c_gused[c*8 +: 8]),
                .func_addr         (func_addr [c*CLUSTER*ADDR_W +: CLUSTER*ADDR_W]),
                .func_we           (func_we   [c*CLUSTER +: CLUSTER]),
                .func_re           (func_re   [c*CLUSTER +: CLUSTER]),
                .func_wdata        (func_wdata[c*CLUSTER*WIDTH +: CLUSTER*WIDTH]),
                .func_rdata        (func_rdata[c*CLUSTER*WIDTH +: CLUSTER*WIDTH])
            );
        end
    endgenerate

    assign bisr_busy         = |c_busy;
    assign bisr_done         = &c_done;
    assign bisr_pass         = &c_pass;
    assign bisr_unrepairable = |c_unrep;
    assign bisr_overflow     = |c_ovf;
    assign bisr_verify_fail  = |c_vfail;

    integer i;
    always @(*) begin
        bisr_fault_count = 16'd0;
        bisr_global_used = 8'd0;
        for (i = 0; i < N_CL; i = i + 1) begin
            bisr_fault_count = bisr_fault_count + c_fcnt[i*16 +: 16];
            bisr_global_used = bisr_global_used + c_gused[i*8 +: 8];
        end
    end

endmodule

`default_nettype wire
