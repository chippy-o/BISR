//============================================================================
// tb_sram_injector.v
// Unit test: sram_wrapper + fault_injector + spare_row_bank.
//
// Checks
//   1. fault-free write/read
//   2. SA0, SA1, TF-up, TF-down on the main array
//   3. local spare access (hit, is_global = 0) and main row left untouched
//   4. disabled spare reads 0 (selective activation)
//   5. global spare read mux + g_we request
//   6. fault injected into a local spare row
//============================================================================
`timescale 1ns/1ps
`include "bisr_defines.vh"

module tb_sram_injector;

    localparam ROWS = 16, WIDTH = 8, N_LOCAL = 2, N_GLOBAL = 2;
    localparam ADDR_W = $clog2(ROWS);
    localparam SIDX_W = 1;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg  [ADDR_W-1:0]         addr = 0;
    reg                       we = 0, re = 0;
    reg  [WIDTH-1:0]          wdata = 0;
    reg                       hit = 0, is_global = 0;
    reg  [SIDX_W-1:0]         sidx = 0;
    reg  [N_LOCAL-1:0]        local_en = 0;
    reg  [N_GLOBAL*WIDTH-1:0] global_rdata = 0;
    wire                      g_we;
    wire [WIDTH-1:0]          rdata;

    sram_wrapper #(
        .ROWS (ROWS), .WIDTH (WIDTH), .N_LOCAL (N_LOCAL), .N_GLOBAL (N_GLOBAL),
        .SPARE_GATING (1), .ADDR_W (ADDR_W), .SIDX_W (SIDX_W), .GLB (N_GLOBAL)
    ) dut (
        .clk (clk), .scan_en (1'b0),
        .addr (addr), .we (we), .re (re), .wdata (wdata),
        .hit (hit), .is_global (is_global), .sidx (sidx),
        .local_en (local_en), .global_rdata (global_rdata),
        .g_we (g_we), .rdata (rdata)
    );

    integer errors = 0;

    task wr(input [ADDR_W-1:0] a, input [WIDTH-1:0] d);
        begin
            @(negedge clk); addr = a; wdata = d; we = 1'b1;
            @(negedge clk); we = 1'b0;
        end
    endtask

    task rd_check(input [ADDR_W-1:0] a, input [WIDTH-1:0] exp, input [8*32-1:0] what);
        begin
            @(negedge clk); addr = a; re = 1'b1;
            @(negedge clk); re = 1'b0;
            if (rdata !== exp) begin
                errors = errors + 1;
                $display("FAIL %0s: row %0d read %h, expected %h", what, a, rdata, exp);
            end else
                $display("ok   %0s: row %0d = %h", what, a, rdata);
        end
    endtask

    initial begin
        // 1. fault-free
        wr(0, 8'hA5);                 rd_check(0, 8'hA5, "fault-free");

        // 2. main-array faults
        dut.u_fi.add_fault(3, 0, `FT_SA0);
        dut.u_fi.add_fault(4, 7, `FT_SA1);
        dut.u_fi.add_fault(5, 2, `FT_TF_UP);
        dut.u_fi.add_fault(6, 5, `FT_TF_DOWN);

        wr(3, 8'hFF);                 rd_check(3, 8'hFE, "SA0 bit0");
        wr(4, 8'h00);                 rd_check(4, 8'h80, "SA1 bit7");
        wr(5, 8'h00); wr(5, 8'hFF);   rd_check(5, 8'hFB, "TF-up bit2");
        wr(6, 8'hFF); wr(6, 8'h00);   rd_check(6, 8'h20, "TF-down bit5");

        // 3. local spare 1 replaces row 3
        local_en = 2'b10; hit = 1'b1; is_global = 1'b0; sidx = 1'b1;
        wr(3, 8'h3C);                 rd_check(3, 8'h3C, "local spare 1");
        hit = 1'b0;                   rd_check(3, 8'hFE, "main row 3 untouched");

        // 4. disabled spare reads 0
        local_en = 2'b00; hit = 1'b1; rd_check(3, 8'h00, "disabled spare = 0");

        // 5. global spare read path + write request
        hit = 1'b1; is_global = 1'b1; sidx = 1'b1;
        global_rdata = {8'h77, 8'h11};
        rd_check(9, 8'h77, "global spare 1 read");
        @(negedge clk); addr = 9; we = 1'b1; #1;
        if (g_we !== 1'b1) begin errors = errors + 1; $display("FAIL g_we not raised"); end
        else $display("ok   g_we raised for global write");
        @(negedge clk); we = 1'b0;

        // 6. fault inside local spare row 0
        dut.u_local.g_row[0].u_fi.add_fault(0, 1, `FT_SA1);
        local_en = 2'b01; hit = 1'b1; is_global = 1'b0; sidx = 1'b0;
        wr(2, 8'h00);                 rd_check(2, 8'h02, "SA1 in local spare 0");

        if (errors == 0) $display("TB_SRAM_INJECTOR: ALL CHECKS PASSED");
        else             $display("TB_SRAM_INJECTOR: %0d CHECK(S) FAILED", errors);
        $finish;
    end

endmodule
