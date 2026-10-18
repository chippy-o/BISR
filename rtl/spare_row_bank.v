//============================================================================
// spare_row_bank.v
// Generic bank of K spare rows, each WIDTH bits wide.
//
// Used twice in the design:
//   * inside every sram_wrapper as that SRAM's LOCAL spare rows (K = N_LOCAL)
//   * once in shared_bisr_top as the shared GLOBAL spare pool (K = N_GLOBAL)
//
// Every row has its own write enable, write data and read data, so different
// memories can access different global spare rows in the same cycle
// (each global row is owned by at most one memory, so no port conflicts).
//
// Selective spare activation (GATING = 1):
//   * the row's clock is gated by spare_en[k]  -> unassigned rows never clock
//   * the row's read data is forced to 0 when disabled -> no mux toggling
// GATING = 0 builds the "all spares always on" variant used as the power
// reference.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module spare_row_bank #(
    parameter K      = 1,       // number of spare rows
    parameter WIDTH  = 8,
    parameter GATING = 1        // 1 = selective activation, 0 = always on
)(
    input  wire               clk,
    input  wire               scan_en,     // forces gated clocks on in scan
    input  wire [K-1:0]       spare_en,    // row k assigned by BIRA
    input  wire [K-1:0]       row_we,      // per-row write enable
    input  wire [K*WIDTH-1:0] row_wdata,   // per-row write data
    output wire [K*WIDTH-1:0] row_rdata    // per-row read data (async)
);

    genvar k;
    generate
        for (k = 0; k < K; k = k + 1) begin : g_row

            wire row_clk;   // clock seen by this row
            wire en_eff;    // effective enable

            if (GATING) begin : g_gate
                assign en_eff = spare_en[k];
                spare_icg u_icg (
                    .clk     (clk),
                    .en      (spare_en[k]),
                    .test_en (scan_en),
                    .gclk    (row_clk)
                );
            end else begin : g_nogate
                assign en_eff  = 1'b1;
                assign row_clk = clk;
            end

            // Row storage (flip-flops, no reset - like SRAM cells)
            reg  [WIDTH-1:0] data;
            wire [WIDTH-1:0] wd;   // data written into the row
            wire [WIDTH-1:0] rd;   // data read from the row

`ifdef FAULT_INJECT
            // One-row fault injector so spare rows can be made faulty too
            fault_injector #(
                .ROWS  (1),
                .WIDTH (WIDTH)
            ) u_fi (
                .addr      (1'b0),
                .wdata_in  (row_wdata[k*WIDTH +: WIDTH]),
                .cur_data  (data),
                .wdata_out (wd),
                .rdata_out (rd)
            );
`else
            assign wd = row_wdata[k*WIDTH +: WIDTH];
            assign rd = data;
`endif

            always @(posedge row_clk) begin
                if (row_we[k])
                    data <= wd;
            end

            // Disabled rows drive 0 so the read mux does not toggle
            assign row_rdata[k*WIDTH +: WIDTH] = en_eff ? rd : {WIDTH{1'b0}};

        end
    endgenerate

endmodule

`default_nettype wire
