//============================================================================
// remap_unit.v
// Address remapping + spare-enable decode for the spare-indexed repair table.
//
// For every memory m (all in parallel, combinational):
//   * local slots of memory m  : compare row with acc_addr[m]
//                                (N_LOCAL comparators, own memory only)
//   * global slots             : compare {owner, row} with {m, acc_addr[m]}
//                                (N_GLOBAL comparators per memory)
//   On a match: hit[m] = 1 and the access is steered to
//               local spare k  (is_global = 0, sidx = k) or
//               global spare g (is_global = 1, sidx = g).
//
// Comparator count: N_MEM*N_LOCAL + N_MEM*N_GLOBAL
// (fault-indexed version: N_MEM*FT_DEPTH, each also comparing a memory id).
// The global term still grows as N_MEM*N_GLOBAL, which is why large
// systems use clustered_bisr_top (bounded N_MEM and N_GLOBAL per cluster).
//
// Spare enables (selective spare activation) are just the slot valid bits.
// Everything is gated by remap_en, raised by the control FSM once the table
// is loaded (LOAD / VERIFY / DONE). This logic is on the memory access path.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module remap_unit #(
    parameter N_MEM    = 2,
    parameter N_LOCAL  = 1,
    parameter N_GLOBAL = 2,
    parameter MEM_W    = 1,
    parameter ADDR_W   = 8,
    parameter SIDX_W   = 1,
    parameter GLB      = (N_GLOBAL > 0) ? N_GLOBAL : 1
)(
    input  wire                              remap_en,

    // current access address of every memory
    input  wire [N_MEM*ADDR_W-1:0]           acc_addr,

    // repair table
    input  wire [N_MEM*N_LOCAL-1:0]          lt_valid,
    input  wire [N_MEM*N_LOCAL*ADDR_W-1:0]   lt_row,
    input  wire [GLB-1:0]                    gt_valid,
    input  wire [GLB*MEM_W-1:0]              gt_mem,
    input  wire [GLB*ADDR_W-1:0]             gt_row,

    // per-memory remap decision
    output reg  [N_MEM-1:0]                  hit,
    output reg  [N_MEM-1:0]                  is_global,
    output reg  [N_MEM*SIDX_W-1:0]           sidx,

    // spare enables
    output wire [N_MEM*N_LOCAL-1:0]          local_en,
    output wire [GLB-1:0]                    global_en
);

    assign local_en  = remap_en ? lt_valid : {N_MEM*N_LOCAL{1'b0}};
    assign global_en = (remap_en && N_GLOBAL > 0) ? gt_valid : {GLB{1'b0}};

    integer m, k, g;

    always @(*) begin
        hit       = {N_MEM{1'b0}};
        is_global = {N_MEM{1'b0}};
        sidx      = {N_MEM*SIDX_W{1'b0}};

        if (remap_en) begin
            for (m = 0; m < N_MEM; m = m + 1) begin
                // own local spares
                for (k = 0; k < N_LOCAL; k = k + 1) begin
                    if (lt_valid[m*N_LOCAL + k] &&
                        lt_row[(m*N_LOCAL + k)*ADDR_W +: ADDR_W] == acc_addr[m*ADDR_W +: ADDR_W]) begin
                        hit[m]                   = 1'b1;
                        is_global[m]             = 1'b0;
                        sidx[m*SIDX_W +: SIDX_W] = k;
                    end
                end
                // global spares owned by this memory
                for (g = 0; g < N_GLOBAL; g = g + 1) begin
                    if (gt_valid[g] &&
                        gt_mem[g*MEM_W +: MEM_W]   == m &&
                        gt_row[g*ADDR_W +: ADDR_W] == acc_addr[m*ADDR_W +: ADDR_W]) begin
                        hit[m]                   = 1'b1;
                        is_global[m]             = 1'b1;
                        sidx[m*SIDX_W +: SIDX_W] = g;
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
