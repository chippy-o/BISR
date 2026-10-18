//============================================================================
// repair_table.v
// Holds the final spare assignments written by the BIRA and read by
// remap_unit on every memory access.
//
// Entry i : { valid, mem_id, faulty_row, is_global, spare_idx }
//
// With N_GLOBAL = 0 the is_global field is tied to 0 (its flops become
// unloaded and are removed by synthesis).
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module repair_table #(
    parameter FT_DEPTH = 8,
    parameter N_GLOBAL = 2,
    parameter MEM_W    = 1,
    parameter ADDR_W   = 8,
    parameter SIDX_W   = 1,
    parameter FIDX_W   = (FT_DEPTH > 1) ? $clog2(FT_DEPTH) : 1
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       clear,

    // write port (from bira)
    input  wire                       we,
    input  wire [FIDX_W-1:0]          idx,
    input  wire                       w_valid,
    input  wire [MEM_W-1:0]           w_mem,
    input  wire [ADDR_W-1:0]          w_row,
    input  wire                       w_is_global,
    input  wire [SIDX_W-1:0]          w_sidx,

    // contents (flattened: entry i at [i*W +: W])
    output reg  [FT_DEPTH-1:0]        rt_valid,
    output reg  [FT_DEPTH*MEM_W-1:0]  rt_mem,
    output reg  [FT_DEPTH*ADDR_W-1:0] rt_row,
    output wire [FT_DEPTH-1:0]        rt_is_global,
    output reg  [FT_DEPTH*SIDX_W-1:0] rt_sidx
);

    reg [FT_DEPTH-1:0] ig_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rt_valid <= {FT_DEPTH{1'b0}};
            rt_mem   <= {FT_DEPTH*MEM_W{1'b0}};
            rt_row   <= {FT_DEPTH*ADDR_W{1'b0}};
            ig_q     <= {FT_DEPTH{1'b0}};
            rt_sidx  <= {FT_DEPTH*SIDX_W{1'b0}};
        end else if (clear) begin
            rt_valid <= {FT_DEPTH{1'b0}};
            rt_mem   <= {FT_DEPTH*MEM_W{1'b0}};
            rt_row   <= {FT_DEPTH*ADDR_W{1'b0}};
            ig_q     <= {FT_DEPTH{1'b0}};
            rt_sidx  <= {FT_DEPTH*SIDX_W{1'b0}};
        end else if (we) begin
            rt_valid[idx]                  <= w_valid;
            rt_mem  [idx*MEM_W  +: MEM_W]  <= w_mem;
            rt_row  [idx*ADDR_W +: ADDR_W] <= w_row;
            ig_q    [idx]                  <= w_is_global;
            rt_sidx [idx*SIDX_W +: SIDX_W] <= w_sidx;
        end
    end

    assign rt_is_global = (N_GLOBAL > 0) ? ig_q : {FT_DEPTH{1'b0}};

endmodule

`default_nettype wire
