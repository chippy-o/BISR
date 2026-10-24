//============================================================================
// repair_table.v
// Final spare assignments written by the BIRA and read by remap_unit on
// every memory access.
//
// SPARE-INDEXED ("split") organisation - one slot per spare row:
//
//   local slot  (m, k) : { valid, faulty_row }          k = 0..N_LOCAL-1
//                        owner is implicit (memory m), so no memory id is
//                        stored and only memory m's address is compared.
//   global slot g      : { valid, owner_mem, faulty_row } g = 0..N_GLOBAL-1
//
// Compared with a fault-indexed table ({mem, row, is_global, sidx} per
// fault-table entry, every entry compared against every memory), this
//   * removes the memory-id compare and the cross-memory compares for local
//     spares (N_MEM*N_LOCAL comparators instead of N_MEM*FT_DEPTH), and
//   * makes the table size independent of FT_DEPTH (it is set by the number
//     of spares, which is also the most rows that can ever be repaired).
//
// The BIRA write port is unchanged: {is_global, sidx} selects the slot, and
// the write happens only when w_valid = 1 (a spare was actually assigned).
// With N_GLOBAL = 0 no global slots are built (dedicated baseline).
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module repair_table #(
    parameter N_MEM    = 2,
    parameter N_LOCAL  = 1,
    parameter N_GLOBAL = 2,
    parameter MEM_W    = 1,
    parameter ADDR_W   = 8,
    parameter SIDX_W   = 1,
    parameter GLB      = (N_GLOBAL > 0) ? N_GLOBAL : 1
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              clear,

    // write port (from bira)
    input  wire                              we,
    input  wire                              w_valid,
    input  wire [MEM_W-1:0]                  w_mem,
    input  wire [ADDR_W-1:0]                 w_row,
    input  wire                              w_is_global,
    input  wire [SIDX_W-1:0]                 w_sidx,

    // local slots: slot (m,k) at index m*N_LOCAL + k
    output wire [N_MEM*N_LOCAL-1:0]          lt_valid,
    output wire [N_MEM*N_LOCAL*ADDR_W-1:0]   lt_row,

    // global slots
    output wire [GLB-1:0]                    gt_valid,
    output wire [GLB*MEM_W-1:0]              gt_mem,
    output wire [GLB*ADDR_W-1:0]             gt_row
);

    wire wr = we & w_valid;

    genvar s;
    generate
        // -------------------------------------------------------------
        // Local slots
        // -------------------------------------------------------------
        for (s = 0; s < N_MEM*N_LOCAL; s = s + 1) begin : g_lslot
            localparam integer M = s / N_LOCAL;
            localparam integer K = s % N_LOCAL;

            wire sel = wr & ~w_is_global & (w_mem == M) & (w_sidx == K);

            reg              v;
            reg [ADDR_W-1:0] row;     // no reset: only meaningful when v = 1

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)      v <= 1'b0;
                else if (clear)  v <= 1'b0;
                else if (sel)    v <= 1'b1;
            end

            always @(posedge clk)
                if (sel) row <= w_row;

            assign lt_valid[s]                = v;
            assign lt_row[s*ADDR_W +: ADDR_W] = row;
        end

        // -------------------------------------------------------------
        // Global slots
        // -------------------------------------------------------------
        if (N_GLOBAL > 0) begin : g_glb
            for (s = 0; s < N_GLOBAL; s = s + 1) begin : g_gslot
                wire sel = wr & w_is_global & (w_sidx == s);

                reg              v;
                reg [MEM_W-1:0]  mem;
                reg [ADDR_W-1:0] row;

                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n)      v <= 1'b0;
                    else if (clear)  v <= 1'b0;
                    else if (sel)    v <= 1'b1;
                end

                always @(posedge clk)
                    if (sel) begin
                        mem <= w_mem;
                        row <= w_row;
                    end

                assign gt_valid[s]                = v;
                assign gt_mem[s*MEM_W +: MEM_W]   = mem;
                assign gt_row[s*ADDR_W +: ADDR_W] = row;
            end
        end else begin : g_noglb
            assign gt_valid = {GLB{1'b0}};
            assign gt_mem   = {GLB*MEM_W{1'b0}};
            assign gt_row   = {GLB*ADDR_W{1'b0}};
        end
    endgenerate

endmodule

`default_nettype wire
