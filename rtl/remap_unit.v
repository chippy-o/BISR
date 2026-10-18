//============================================================================
// remap_unit.v
// Address remapping + spare-enable decode, shared by all memories.
//
// For every memory m (all in parallel, combinational):
//   compare (m, acc_addr[m]) with every valid repair-table entry (CAM).
//   On a match: hit[m] = 1 and the access is steered to
//               local spare sidx    (is_global = 0) or
//               global spare sidx   (is_global = 1).
//
// Spare enables (selective spare activation):
//   local_en [m*N_LOCAL + k] = local spare k of memory m is assigned
//   global_en[k]             = global spare k is assigned
//
// Everything is gated by remap_en, which the control FSM raises once the
// repair table has been loaded (LOAD / VERIFY / DONE).
//
// This CAM sits on the memory access path: address -> compare -> spare
// select is the timing path to report.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module remap_unit #(
    parameter N_MEM    = 2,
    parameter FT_DEPTH = 8,
    parameter N_LOCAL  = 1,
    parameter N_GLOBAL = 2,
    parameter MEM_W    = 1,
    parameter ADDR_W   = 8,
    parameter SIDX_W   = 1,
    parameter GLB      = (N_GLOBAL > 0) ? N_GLOBAL : 1
)(
    input  wire                       remap_en,

    // current access address of every memory
    input  wire [N_MEM*ADDR_W-1:0]    acc_addr,

    // repair table
    input  wire [FT_DEPTH-1:0]        rt_valid,
    input  wire [FT_DEPTH*MEM_W-1:0]  rt_mem,
    input  wire [FT_DEPTH*ADDR_W-1:0] rt_row,
    input  wire [FT_DEPTH-1:0]        rt_is_global,
    input  wire [FT_DEPTH*SIDX_W-1:0] rt_sidx,

    // per-memory remap decision
    output reg  [N_MEM-1:0]           hit,
    output reg  [N_MEM-1:0]           is_global,
    output reg  [N_MEM*SIDX_W-1:0]    sidx,

    // spare enables
    output reg  [N_MEM*N_LOCAL-1:0]   local_en,
    output reg  [GLB-1:0]             global_en
);

    integer m, i;

    always @(*) begin
        hit       = {N_MEM{1'b0}};
        is_global = {N_MEM{1'b0}};
        sidx      = {N_MEM*SIDX_W{1'b0}};
        local_en  = {N_MEM*N_LOCAL{1'b0}};
        global_en = {GLB{1'b0}};

        if (remap_en) begin
            for (i = 0; i < FT_DEPTH; i = i + 1) begin
                if (rt_valid[i]) begin
                    // spare enable decode
                    if (rt_is_global[i])
                        global_en[rt_sidx[i*SIDX_W +: SIDX_W]] = 1'b1;
                    else
                        local_en[rt_mem[i*MEM_W +: MEM_W]*N_LOCAL +
                                 rt_sidx[i*SIDX_W +: SIDX_W]]  = 1'b1;

                    // address compare for every memory
                    for (m = 0; m < N_MEM; m = m + 1) begin
                        if (rt_mem[i*MEM_W +: MEM_W]   == m &&
                            rt_row[i*ADDR_W +: ADDR_W] == acc_addr[m*ADDR_W +: ADDR_W]) begin
                            hit[m]                    = 1'b1;
                            is_global[m]              = rt_is_global[i];
                            sidx[m*SIDX_W +: SIDX_W]  = rt_sidx[i*SIDX_W +: SIDX_W];
                        end
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire
