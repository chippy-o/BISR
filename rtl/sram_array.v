//============================================================================
// sram_array.v
// Behavioural single-port storage array, ROWS x WIDTH.
//
//  * Write : synchronous (on posedge clk when we = 1)
//  * Read  : asynchronous (rdata always shows mem[addr])
//
// The registered read stage is in sram_wrapper, so the wrapper as a whole
// behaves like a synchronous SRAM with a 1-cycle read latency.
//
// This module is deliberately kept on its own so that:
//  * synthesis can black-box it (area then reflects only the BISR logic), and
//  * it can later be swapped for a compiled SRAM macro.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module sram_array #(
    parameter ROWS   = 256,
    parameter WIDTH  = 8,
    // derived - do not override
    parameter ADDR_W = (ROWS > 1) ? $clog2(ROWS) : 1
)(
    input  wire              clk,
    input  wire              we,      // write enable
    input  wire [ADDR_W-1:0] addr,    // row address
    input  wire [WIDTH-1:0]  wdata,   // write data
    output wire [WIDTH-1:0]  rdata    // current contents of mem[addr]
);

    // Storage. Not reset - real SRAM cells power up unknown.
    reg [WIDTH-1:0] mem [0:ROWS-1];

    always @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
    end

    assign rdata = mem[addr];

endmodule

`default_nettype wire
