//============================================================================
// bira.v
// Built-In Redundancy Analysis - single-pass, deterministic allocation.
//
// After the TEST phase, walks the fault table once (one entry per cycle) and
// gives each faulty row a spare:
//
//   1. the next free LOCAL spare of that row's memory, else
//   2. the next free GLOBAL spare from the shared pool, else
//   3. nothing -> `unrepairable` is set.
//
// Fault-table overflow also makes the system unrepairable (a faulty row was
// never logged, so it cannot be repaired).
//
// Each decision is written straight into repair_table at the same index as
// the fault-table entry (rt_we / rt_idx / rt_*). Entries that receive no
// spare are written as invalid.
//
// With N_GLOBAL = 0 the global branch is constant-false, which gives the
// dedicated (local-only) BIRA used by the baseline.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module bira #(
    parameter N_MEM    = 2,
    parameter FT_DEPTH = 8,
    parameter N_LOCAL  = 1,
    parameter N_GLOBAL = 2,
    // derived - passed down from the top
    parameter MEM_W    = (N_MEM > 1) ? $clog2(N_MEM) : 1,
    parameter ADDR_W   = 8,
    parameter SIDX_W   = 1,
    parameter LCNT_W   = $clog2(N_LOCAL + 1),
    parameter GCNT_W   = (N_GLOBAL > 0) ? $clog2(N_GLOBAL + 1) : 1,
    parameter FIDX_W   = (FT_DEPTH > 1) ? $clog2(FT_DEPTH) : 1
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       start,          // 1-cycle pulse

    // fault table (from fault_logger)
    input  wire [FT_DEPTH-1:0]        ft_valid,
    input  wire [FT_DEPTH*MEM_W-1:0]  ft_mem,
    input  wire [FT_DEPTH*ADDR_W-1:0] ft_row,
    input  wire                       ft_overflow,

    output wire                       busy,
    output wire                       done,           // 1-cycle pulse

    // repair-table write port
    output wire                       rt_we,
    output wire [FIDX_W-1:0]          rt_idx,
    output wire                       rt_valid,
    output wire [MEM_W-1:0]           rt_mem,
    output wire [ADDR_W-1:0]          rt_row,
    output wire                       rt_is_global,
    output wire [SIDX_W-1:0]          rt_sidx,

    // results
    output reg                        unrepairable,
    output wire [N_MEM*LCNT_W-1:0]    local_used,     // local spares used per memory
    output reg  [GCNT_W-1:0]          global_used     // global spares used
);

    localparam [1:0] S_IDLE = 2'd0,
                     S_RUN  = 2'd1,
                     S_FIN  = 2'd2;

    reg [1:0]              state;
    reg [FIDX_W-1:0]       idx;       // fault-table entry being processed
    reg [N_MEM*LCNT_W-1:0] lu;        // local spares used, per memory

    assign local_used = lu;

    // ------------------------------------------------------------------
    // Decision for the current entry (combinational)
    // ------------------------------------------------------------------
    wire              cur_valid = ft_valid[idx];
    wire [MEM_W-1:0]  cur_mem   = ft_mem[idx*MEM_W +: MEM_W];
    wire [ADDR_W-1:0] cur_row   = ft_row[idx*ADDR_W +: ADDR_W];
    wire [LCNT_W-1:0] cur_lu    = lu[cur_mem*LCNT_W +: LCNT_W];

    wire can_local  = (cur_lu < N_LOCAL);
    wire can_global = (N_GLOBAL > 0) && (global_used < N_GLOBAL);

    assign rt_we        = (state == S_RUN);
    assign rt_idx       = idx;
    assign rt_valid     = cur_valid & (can_local | can_global);
    assign rt_mem       = cur_mem;
    assign rt_row       = cur_row;
    assign rt_is_global = ~can_local;
    assign rt_sidx      = can_local ? cur_lu : global_used;

    // ------------------------------------------------------------------
    // Sequencer
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            idx          <= {FIDX_W{1'b0}};
            lu           <= {N_MEM*LCNT_W{1'b0}};
            global_used  <= {GCNT_W{1'b0}};
            unrepairable <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state        <= S_RUN;
                        idx          <= {FIDX_W{1'b0}};
                        lu           <= {N_MEM*LCNT_W{1'b0}};
                        global_used  <= {GCNT_W{1'b0}};
                        unrepairable <= ft_overflow;
                    end
                end

                S_RUN: begin
                    if (cur_valid) begin
                        if (can_local)
                            lu[cur_mem*LCNT_W +: LCNT_W] <= cur_lu + 1'b1;
                        else if (can_global)
                            global_used <= global_used + 1'b1;
                        else
                            unrepairable <= 1'b1;
                    end
                    if (idx == FT_DEPTH - 1)
                        state <= S_FIN;
                    else
                        idx <= idx + 1'b1;
                end

                default: state <= S_IDLE;   // S_FIN
            endcase
        end
    end

    assign busy = (state != S_IDLE);
    assign done = (state == S_FIN);

endmodule

`default_nettype wire
