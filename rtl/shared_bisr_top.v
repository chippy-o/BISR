//============================================================================
// shared_bisr_top.v
// PROPOSED ARCHITECTURE: one shared BISR controller for N_MEM SRAMs, with
// N_LOCAL local spare rows per SRAM and a shared pool of N_GLOBAL spare rows.
//
//   bisr_ctrl_fsm --+--> march_cminus --> fault_logger --> bira --> repair_table
//                   |                                                   |
//                   +----------------------- remap_unit <---------------+
//                                                |
//         func ports --> [port mux] --> sram_wrapper[0..N-1] <--> global pool
//
// Port mux: in TEST/VERIFY the MBIST drives the selected memory; otherwise
// the functional ports drive the memories (blocked while the BISR is busy).
//
// Parameters
//   N_MEM        number of SRAMs served by the one controller
//   ROWS, WIDTH  SRAM size (rows x bits)
//   N_LOCAL      local spare rows per SRAM (>= 1)
//   N_GLOBAL     shared global spare rows (0 = no pool)
//   FT_DEPTH     fault-table / repair-table entries
//   SPARE_GATING 1 = selective spare activation, 0 = all spares clocked
//
// The `derived` parameters must not be overridden.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module shared_bisr_top #(
    parameter N_MEM        = 2,
    parameter ROWS         = 256,
    parameter WIDTH        = 8,
    parameter N_LOCAL      = 1,
    parameter N_GLOBAL     = 2,
    parameter FT_DEPTH     = 8,
    parameter SPARE_GATING = 1,
    // derived - do not override
    parameter ADDR_W = (ROWS > 1)     ? $clog2(ROWS)         : 1,
    parameter MEM_W  = (N_MEM > 1)    ? $clog2(N_MEM)        : 1,
    parameter LIDX_W = (N_LOCAL > 1)  ? $clog2(N_LOCAL)      : 1,
    parameter GIDX_W = (N_GLOBAL > 1) ? $clog2(N_GLOBAL)     : 1,
    parameter SIDX_W = (LIDX_W > GIDX_W) ? LIDX_W : GIDX_W,
    parameter LCNT_W = $clog2(N_LOCAL + 1),
    parameter GCNT_W = (N_GLOBAL > 0) ? $clog2(N_GLOBAL + 1) : 1,
    parameter FIDX_W = (FT_DEPTH > 1) ? $clog2(FT_DEPTH)     : 1,
    parameter FCNT_W = $clog2(FT_DEPTH + 1),
    parameter GLB    = (N_GLOBAL > 0) ? N_GLOBAL : 1
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      scan_en,          // tie 0 in functional use

    // BISR control / status
    input  wire                      bisr_start,       // 1-cycle pulse
    output wire                      bisr_busy,
    output wire                      bisr_done,        // level, held in DONE
    output wire                      bisr_pass,
    output wire                      bisr_unrepairable,
    output wire                      bisr_overflow,
    output wire                      bisr_verify_fail,
    output wire [15:0]               bisr_fault_count, // faulty rows logged
    output wire [N_MEM*LCNT_W-1:0]   bisr_local_used,  // local spares used / SRAM
    output wire [7:0]                bisr_global_used, // global spares used

    // functional memory ports (one per SRAM, 1-cycle read latency)
    input  wire [N_MEM*ADDR_W-1:0]   func_addr,
    input  wire [N_MEM-1:0]          func_we,
    input  wire [N_MEM-1:0]          func_re,
    input  wire [N_MEM*WIDTH-1:0]    func_wdata,
    output wire [N_MEM*WIDTH-1:0]    func_rdata
);

    // ==================================================================
    // Control FSM
    // ==================================================================
    wire c_clear, c_mb_start, c_bira_start, c_log_en, c_remap_en, c_bist_mode;
    wire mb_done, br_done, br_unrep;
    wire fl_valid;

    bisr_ctrl_fsm u_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (bisr_start),
        .mbist_done   (mb_done),
        .bira_done    (br_done),
        .bira_unrep   (br_unrep),
        .fail_valid   (fl_valid),
        .clear        (c_clear),
        .mbist_start  (c_mb_start),
        .bira_start   (c_bira_start),
        .log_en       (c_log_en),
        .remap_en     (c_remap_en),
        .bist_mode    (c_bist_mode),
        .busy         (bisr_busy),
        .done         (bisr_done),
        .pass         (bisr_pass),
        .unrepairable (bisr_unrepairable),
        .verify_fail  (bisr_verify_fail),
        .state        ()
    );

    // ==================================================================
    // MBIST (shared March C-)
    // ==================================================================
    wire [MEM_W-1:0]  mb_mem;
    wire [ADDR_W-1:0] mb_addr;
    wire              mb_we, mb_re, mb_busy;
    wire [WIDTH-1:0]  mb_wdata;
    wire [MEM_W-1:0]  fl_mem;
    wire [ADDR_W-1:0] fl_row;
    wire [WIDTH-1:0]  fl_bits;
    wire              fl_exp;
    wire [2:0]        fl_elem;

    march_cminus #(
        .N_MEM  (N_MEM),
        .ROWS   (ROWS),
        .WIDTH  (WIDTH),
        .ADDR_W (ADDR_W),
        .MEM_W  (MEM_W)
    ) u_mbist (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (c_mb_start),
        .busy       (mb_busy),
        .done       (mb_done),
        .mem_sel    (mb_mem),
        .addr       (mb_addr),
        .we         (mb_we),
        .re         (mb_re),
        .wdata      (mb_wdata),
        .rdata_bus  (func_rdata),
        .fail_valid (fl_valid),
        .fail_mem   (fl_mem),
        .fail_row   (fl_row),
        .fail_bits  (fl_bits),
        .fail_exp   (fl_exp),
        .fail_elem  (fl_elem)
    );

    // ==================================================================
    // Fault logger
    // ==================================================================
    wire [FT_DEPTH-1:0]        ft_valid;
    wire [FT_DEPTH*MEM_W-1:0]  ft_mem;
    wire [FT_DEPTH*ADDR_W-1:0] ft_row;
    wire [FT_DEPTH*WIDTH-1:0]  ft_mask;
    wire [FT_DEPTH*2-1:0]      ft_class;
    wire [FCNT_W-1:0]          ft_count;

    fault_logger #(
        .FT_DEPTH (FT_DEPTH),
        .MEM_W    (MEM_W),
        .ADDR_W   (ADDR_W),
        .WIDTH    (WIDTH)
    ) u_logger (
        .clk        (clk),
        .rst_n      (rst_n),
        .clear      (c_clear),
        .log_en     (c_log_en),
        .fail_valid (fl_valid),
        .fail_mem   (fl_mem),
        .fail_row   (fl_row),
        .fail_bits  (fl_bits),
        .fail_exp   (fl_exp),
        .ft_valid   (ft_valid),
        .ft_mem     (ft_mem),
        .ft_row     (ft_row),
        .ft_mask    (ft_mask),
        .ft_class   (ft_class),
        .overflow   (bisr_overflow),
        .count      (ft_count)
    );

    assign bisr_fault_count = ft_count;

    // ==================================================================
    // BIRA
    // ==================================================================
    wire              w_rt_we, w_rt_valid, w_rt_is_global;
    wire [FIDX_W-1:0] w_rt_idx;
    wire [MEM_W-1:0]  w_rt_mem;
    wire [ADDR_W-1:0] w_rt_row;
    wire [SIDX_W-1:0] w_rt_sidx;
    wire [GCNT_W-1:0] br_gused;
    wire              br_busy;

    bira #(
        .N_MEM    (N_MEM),
        .FT_DEPTH (FT_DEPTH),
        .N_LOCAL  (N_LOCAL),
        .N_GLOBAL (N_GLOBAL),
        .MEM_W    (MEM_W),
        .ADDR_W   (ADDR_W),
        .SIDX_W   (SIDX_W),
        .LCNT_W   (LCNT_W),
        .GCNT_W   (GCNT_W),
        .FIDX_W   (FIDX_W)
    ) u_bira (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (c_bira_start),
        .ft_valid     (ft_valid),
        .ft_mem       (ft_mem),
        .ft_row       (ft_row),
        .ft_overflow  (bisr_overflow),
        .busy         (br_busy),
        .done         (br_done),
        .rt_we        (w_rt_we),
        .rt_idx       (w_rt_idx),
        .rt_valid     (w_rt_valid),
        .rt_mem       (w_rt_mem),
        .rt_row       (w_rt_row),
        .rt_is_global (w_rt_is_global),
        .rt_sidx      (w_rt_sidx),
        .unrepairable (br_unrep),
        .local_used   (bisr_local_used),
        .global_used  (br_gused)
    );

    assign bisr_global_used = br_gused;

    // ==================================================================
    // Repair table
    // ==================================================================
    wire [FT_DEPTH-1:0]        rt_valid;
    wire [FT_DEPTH*MEM_W-1:0]  rt_mem;
    wire [FT_DEPTH*ADDR_W-1:0] rt_row;
    wire [FT_DEPTH-1:0]        rt_is_global;
    wire [FT_DEPTH*SIDX_W-1:0] rt_sidx;

    repair_table #(
        .FT_DEPTH (FT_DEPTH),
        .N_GLOBAL (N_GLOBAL),
        .MEM_W    (MEM_W),
        .ADDR_W   (ADDR_W),
        .SIDX_W   (SIDX_W),
        .FIDX_W   (FIDX_W)
    ) u_rtable (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear        (c_clear),
        .we           (w_rt_we),
        .idx          (w_rt_idx),
        .w_valid      (w_rt_valid),
        .w_mem        (w_rt_mem),
        .w_row        (w_rt_row),
        .w_is_global  (w_rt_is_global),
        .w_sidx       (w_rt_sidx),
        .rt_valid     (rt_valid),
        .rt_mem       (rt_mem),
        .rt_row       (rt_row),
        .rt_is_global (rt_is_global),
        .rt_sidx      (rt_sidx)
    );

    // ==================================================================
    // Port mux: MBIST or functional access for every memory
    // ==================================================================
    wire [N_MEM*ADDR_W-1:0] acc_addr;
    wire [N_MEM-1:0]        acc_we, acc_re;
    wire [N_MEM*WIDTH-1:0]  acc_wdata;

    genvar g;
    generate
        for (g = 0; g < N_MEM; g = g + 1) begin : g_mux
            wire sel = (mb_mem == g);   // memory currently under test
            assign acc_addr [g*ADDR_W +: ADDR_W] = c_bist_mode ? mb_addr  : func_addr [g*ADDR_W +: ADDR_W];
            assign acc_wdata[g*WIDTH  +: WIDTH]  = c_bist_mode ? mb_wdata : func_wdata[g*WIDTH  +: WIDTH];
            assign acc_we[g] = c_bist_mode ? (mb_we & sel) : (func_we[g] & ~bisr_busy);
            assign acc_re[g] = c_bist_mode ? (mb_re & sel) : (func_re[g] & ~bisr_busy);
        end
    endgenerate

    // ==================================================================
    // Remap + spare enables
    // ==================================================================
    wire [N_MEM-1:0]         r_hit, r_is_global;
    wire [N_MEM*SIDX_W-1:0]  r_sidx;
    wire [N_MEM*N_LOCAL-1:0] r_local_en;
    wire [GLB-1:0]           r_global_en;

    remap_unit #(
        .N_MEM    (N_MEM),
        .FT_DEPTH (FT_DEPTH),
        .N_LOCAL  (N_LOCAL),
        .N_GLOBAL (N_GLOBAL),
        .MEM_W    (MEM_W),
        .ADDR_W   (ADDR_W),
        .SIDX_W   (SIDX_W),
        .GLB      (GLB)
    ) u_remap (
        .remap_en     (c_remap_en),
        .acc_addr     (acc_addr),
        .rt_valid     (rt_valid),
        .rt_mem       (rt_mem),
        .rt_row       (rt_row),
        .rt_is_global (rt_is_global),
        .rt_sidx      (rt_sidx),
        .hit          (r_hit),
        .is_global    (r_is_global),
        .sidx         (r_sidx),
        .local_en     (r_local_en),
        .global_en    (r_global_en)
    );

    // ==================================================================
    // SRAMs (each with its local spares)
    // ==================================================================
    wire [N_MEM-1:0]     g_we;        // write request to the global pool
    wire [GLB*WIDTH-1:0] g_rdata;     // read data of every global row

    generate
        for (g = 0; g < N_MEM; g = g + 1) begin : g_mem
            sram_wrapper #(
                .ROWS         (ROWS),
                .WIDTH        (WIDTH),
                .N_LOCAL      (N_LOCAL),
                .N_GLOBAL     (N_GLOBAL),
                .SPARE_GATING (SPARE_GATING),
                .ADDR_W       (ADDR_W),
                .SIDX_W       (SIDX_W),
                .GLB          (GLB)
            ) u_wrap (
                .clk          (clk),
                .scan_en      (scan_en),
                .addr         (acc_addr [g*ADDR_W +: ADDR_W]),
                .we           (acc_we[g]),
                .re           (acc_re[g]),
                .wdata        (acc_wdata[g*WIDTH +: WIDTH]),
                .hit          (r_hit[g]),
                .is_global    (r_is_global[g]),
                .sidx         (r_sidx[g*SIDX_W +: SIDX_W]),
                .local_en     (r_local_en[g*N_LOCAL +: N_LOCAL]),
                .global_rdata (g_rdata),
                .g_we         (g_we[g]),
                .rdata        (func_rdata[g*WIDTH +: WIDTH])
            );
        end
    endgenerate

    // ==================================================================
    // Shared global spare pool
    // ==================================================================
    generate
        if (N_GLOBAL > 0) begin : g_glb
            // Route each memory's global write to the row it owns.
            // A global row belongs to at most one memory, so at most one
            // memory writes a given row in any cycle.
            reg [N_GLOBAL-1:0]       gp_we;
            reg [N_GLOBAL*WIDTH-1:0] gp_wdata;
            integer m;

            always @(*) begin
                gp_we    = {N_GLOBAL{1'b0}};
                gp_wdata = {N_GLOBAL*WIDTH{1'b0}};
                for (m = 0; m < N_MEM; m = m + 1) begin
                    if (g_we[m]) begin
                        gp_we[r_sidx[m*SIDX_W +: SIDX_W]] = 1'b1;
                        gp_wdata[r_sidx[m*SIDX_W +: SIDX_W]*WIDTH +: WIDTH] =
                            acc_wdata[m*WIDTH +: WIDTH];
                    end
                end
            end

            spare_row_bank #(
                .K      (N_GLOBAL),
                .WIDTH  (WIDTH),
                .GATING (SPARE_GATING)
            ) u_pool (
                .clk       (clk),
                .scan_en   (scan_en),
                .spare_en  (r_global_en),
                .row_we    (gp_we),
                .row_wdata (gp_wdata),
                .row_rdata (g_rdata)
            );
        end else begin : g_noglb
            assign g_rdata = {GLB*WIDTH{1'b0}};
        end
    endgenerate

endmodule

`default_nettype wire
