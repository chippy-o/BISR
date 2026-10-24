//============================================================================
// clustered_bisr_top.v
// SCALABLE ARCHITECTURE: N_MEM SRAMs split into clusters of CLUSTER SRAMs.
// Each cluster is one shared_bisr_top (one controller, one March C- MBIST,
// one fault logger / BIRA / repair table / remap, and its own global pool of
// N_GLOBAL spare rows). SRAMs borrow global spares only inside their cluster.
//
// Why: inside one shared controller the remap compares every memory with
// every global slot (N_MEM * N_GLOBAL comparators). With the global pool
// growing with N (N_GLOBAL = N), that is O(N^2). Bounding the cluster size
// makes the total O(N): N/CLUSTER clusters, each with CLUSTER*N_GLOBAL
// comparators. The cluster size trades repair flexibility (how many SRAMs
// can share a pool) against remap area.
//
//   CLUSTER = N_MEM                 -> identical to shared_bisr_top
//   CLUSTER = 1, N_GLOBAL = 0       -> identical to dedicated_bisr_top
//
// Clusters run their BISR in parallel, so test time is set by CLUSTER, not
// by N_MEM. Ports match shared_bisr_top; memory m is SRAM (m % CLUSTER) of
// cluster (m / CLUSTER). Status outputs are combined across clusters.
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
