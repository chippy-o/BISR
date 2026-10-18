//============================================================================
// sram_wrapper.v
// One repairable SRAM: main array + its local spare rows + the main/spare
// read mux + a registered read port.
//
//           addr/we/wdata                          hit/is_global/sidx
//                |                                  (from remap_unit)
//      +---------+-----------+-------------------+
//      |         |           |                   |
//  [main array] [local spares]          (global pool lives in the top;
//      |         |                       this wrapper raises g_we and reads
//      +----+----+---- global_rdata ---  global_rdata[sidx])
//           |
//        read mux --> rdata register (1-cycle read latency)
//
//  * hit = 0 : access goes to the main array
//  * hit = 1, is_global = 0 : access goes to local spare row `sidx`
//  * hit = 1, is_global = 1 : access goes to global spare row `sidx`
//    (write is performed by the global pool in the top using g_we)
//
// A repaired (faulty) main row is never written again.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module sram_wrapper #(
    parameter ROWS         = 256,
    parameter WIDTH        = 8,
    parameter N_LOCAL      = 1,
    parameter N_GLOBAL     = 2,
    parameter SPARE_GATING = 1,
    // derived - passed down from the top
    parameter ADDR_W       = (ROWS > 1) ? $clog2(ROWS) : 1,
    parameter SIDX_W       = 1,
    parameter GLB          = (N_GLOBAL > 0) ? N_GLOBAL : 1
)(
    input  wire                 clk,
    input  wire                 scan_en,

    // memory port (from functional logic or MBIST, already muxed)
    input  wire [ADDR_W-1:0]    addr,
    input  wire                 we,
    input  wire                 re,
    input  wire [WIDTH-1:0]     wdata,

    // remap decision for this access (from remap_unit)
    input  wire                 hit,
    input  wire                 is_global,
    input  wire [SIDX_W-1:0]    sidx,

    // spare enables
    input  wire [N_LOCAL-1:0]   local_en,

    // global pool interface
    input  wire [GLB*WIDTH-1:0] global_rdata,  // read data of every global row
    output wire                 g_we,          // write goes to global row sidx

    // registered read data
    output reg  [WIDTH-1:0]     rdata
);

    // ------------------------------------------------------------------
    // Main array (+ optional fault injector)
    // ------------------------------------------------------------------
    wire             main_we = we & ~hit;   // repaired rows are not written
    wire [WIDTH-1:0] arr_rdata;             // raw array contents at addr
    wire [WIDTH-1:0] arr_wdata;             // data written into the array
    wire [WIDTH-1:0] main_rdata;            // data seen on a read

`ifdef FAULT_INJECT
    fault_injector #(
        .ROWS  (ROWS),
        .WIDTH (WIDTH)
    ) u_fi (
        .addr      (addr),
        .wdata_in  (wdata),
        .cur_data  (arr_rdata),
        .wdata_out (arr_wdata),
        .rdata_out (main_rdata)
    );
`else
    assign arr_wdata  = wdata;
    assign main_rdata = arr_rdata;
`endif

    sram_array #(
        .ROWS  (ROWS),
        .WIDTH (WIDTH)
    ) u_array (
        .clk   (clk),
        .we    (main_we),
        .addr  (addr),
        .wdata (arr_wdata),
        .rdata (arr_rdata)
    );

    // ------------------------------------------------------------------
    // Local spare rows
    // ------------------------------------------------------------------
    wire [N_LOCAL-1:0]       l_we;
    wire [N_LOCAL*WIDTH-1:0] l_wdata;
    wire [N_LOCAL*WIDTH-1:0] l_rdata;

    genvar k;
    generate
        for (k = 0; k < N_LOCAL; k = k + 1) begin : g_lwe
            assign l_we[k]                  = we & hit & ~is_global & (sidx == k);
            assign l_wdata[k*WIDTH +: WIDTH] = wdata;
        end
    endgenerate

    spare_row_bank #(
        .K      (N_LOCAL),
        .WIDTH  (WIDTH),
        .GATING (SPARE_GATING)
    ) u_local (
        .clk       (clk),
        .scan_en   (scan_en),
        .spare_en  (local_en),
        .row_we    (l_we),
        .row_wdata (l_wdata),
        .row_rdata (l_rdata)
    );

    // ------------------------------------------------------------------
    // Global pool write request (performed in the top)
    // ------------------------------------------------------------------
    assign g_we = we & hit & is_global;

    // ------------------------------------------------------------------
    // Read mux + output register
    // ------------------------------------------------------------------
    wire [WIDTH-1:0] rd_mux = !hit      ? main_rdata :
                              is_global ? global_rdata[sidx*WIDTH +: WIDTH] :
                                          l_rdata[sidx*WIDTH +: WIDTH];

    always @(posedge clk) begin
        if (re)
            rdata <= rd_mux;
    end

endmodule

`default_nettype wire
