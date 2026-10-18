//============================================================================
// spare_icg.v
// Behavioural integrated clock gate (latch + AND) used for selective spare
// activation: a spare row's flip-flops only receive a clock when the BIRA has
// assigned that spare.
//
//   * The latch is transparent while clk is LOW, so `en` is captured before
//     the rising edge and gclk cannot glitch.
//   * test_en forces the clock on (for scan shift).
//
// For synthesis, replace this model with the library ICG cell
// (e.g. TLATNTSCAX* in gsclib090, CKLNQD* in TSMC libraries), or let the tool
// map it with set_clock_gating_style / clock-gating insertion.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module spare_icg (
    input  wire clk,
    input  wire en,        // functional enable (spare assigned)
    input  wire test_en,   // scan-mode override
    output wire gclk       // gated clock
);

    reg en_latch;

    // Low-transparent latch
    always @(clk or en or test_en) begin
        if (!clk)
            en_latch <= en | test_en;
    end

    assign gclk = clk & en_latch;

endmodule

`default_nettype wire
