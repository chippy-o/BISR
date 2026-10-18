//============================================================================
// fault_logger.v
// Fault table filled by the MBIST during the TEST phase.
//
// Entry i : { valid, mem_id, row, fail_mask, fail_class }
//   fail_mask  : OR of all failing bits seen in that row
//   fail_class : bit0 = read 1 where 0 expected (SA1 / TF-down)
//                bit1 = read 0 where 1 expected (SA0 / TF-up)
//
// Behaviour
//   * A fail on a (mem, row) already in the table is MERGED into that entry
//     (a row needs one spare no matter how many of its bits are bad).
//   * A fail on a new row takes the next free entry.
//   * A new row with the table full sets `overflow` (that row is lost, so the
//     BIRA will declare the memory system unrepairable).
//
// Entries are filled in order and never removed (until `clear`), so the next
// free entry is simply `count`.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module fault_logger #(
    parameter FT_DEPTH = 8,
    parameter MEM_W    = 1,
    parameter ADDR_W   = 8,
    parameter WIDTH    = 8,
    // derived
    parameter FIDX_W   = (FT_DEPTH > 1) ? $clog2(FT_DEPTH) : 1,
    parameter FCNT_W   = $clog2(FT_DEPTH + 1)
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       clear,      // empty the table
    input  wire                       log_en,     // only log in TEST phase

    // fail report from march_cminus
    input  wire                       fail_valid,
    input  wire [MEM_W-1:0]           fail_mem,
    input  wire [ADDR_W-1:0]          fail_row,
    input  wire [WIDTH-1:0]           fail_bits,
    input  wire                       fail_exp,

    // table contents (flattened: entry i at [i*W +: W])
    output reg  [FT_DEPTH-1:0]        ft_valid,
    output reg  [FT_DEPTH*MEM_W-1:0]  ft_mem,
    output reg  [FT_DEPTH*ADDR_W-1:0] ft_row,
    output reg  [FT_DEPTH*WIDTH-1:0]  ft_mask,
    output reg  [FT_DEPTH*2-1:0]      ft_class,

    output reg                        overflow,
    output reg  [FCNT_W-1:0]          count       // number of faulty rows logged
);

    // ------------------------------------------------------------------
    // CAM lookup: is this (mem,row) already in the table?
    // ------------------------------------------------------------------
    reg              hit;
    reg [FIDX_W-1:0] hit_idx;
    integer i;

    always @(*) begin
        hit     = 1'b0;
        hit_idx = {FIDX_W{1'b0}};
        for (i = 0; i < FT_DEPTH; i = i + 1) begin
            if (!hit && ft_valid[i] &&
                ft_mem[i*MEM_W +: MEM_W]   == fail_mem &&
                ft_row[i*ADDR_W +: ADDR_W] == fail_row) begin
                hit     = 1'b1;
                hit_idx = i;
            end
        end
    end

    wire       full      = (count == FT_DEPTH);
    wire [1:0] new_class = fail_exp ? 2'b10 : 2'b01;
    wire [FIDX_W-1:0] ins_idx = count[FIDX_W-1:0];

    // ------------------------------------------------------------------
    // Table update
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ft_valid <= {FT_DEPTH{1'b0}};
            ft_mem   <= {FT_DEPTH*MEM_W{1'b0}};
            ft_row   <= {FT_DEPTH*ADDR_W{1'b0}};
            ft_mask  <= {FT_DEPTH*WIDTH{1'b0}};
            ft_class <= {FT_DEPTH*2{1'b0}};
            overflow <= 1'b0;
            count    <= {FCNT_W{1'b0}};
        end else if (clear) begin
            ft_valid <= {FT_DEPTH{1'b0}};
            ft_mem   <= {FT_DEPTH*MEM_W{1'b0}};
            ft_row   <= {FT_DEPTH*ADDR_W{1'b0}};
            ft_mask  <= {FT_DEPTH*WIDTH{1'b0}};
            ft_class <= {FT_DEPTH*2{1'b0}};
            overflow <= 1'b0;
            count    <= {FCNT_W{1'b0}};
        end else if (log_en && fail_valid) begin
            if (hit) begin
                // merge into the existing entry
                ft_mask [hit_idx*WIDTH +: WIDTH] <= ft_mask [hit_idx*WIDTH +: WIDTH] | fail_bits;
                ft_class[hit_idx*2 +: 2]         <= ft_class[hit_idx*2 +: 2]         | new_class;
            end else if (!full) begin
                // new faulty row
                ft_valid[ins_idx]                <= 1'b1;
                ft_mem  [ins_idx*MEM_W  +: MEM_W]  <= fail_mem;
                ft_row  [ins_idx*ADDR_W +: ADDR_W] <= fail_row;
                ft_mask [ins_idx*WIDTH  +: WIDTH]  <= fail_bits;
                ft_class[ins_idx*2 +: 2]           <= new_class;
                count <= count + 1'b1;
            end else begin
                overflow <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
