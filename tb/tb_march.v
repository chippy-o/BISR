//============================================================================
// tb_march.v
// Unit test: march_cminus driving two sram_wrappers (no remapping).
//
// Checks
//   * fault-free run: no fails, exactly 10 * ROWS * N_MEM memory operations
//   * each fault model is detected, in the right memory/row, and first seen
//     in the expected March element:
//       SA1 -> E1, SA0 -> E2, TF-up -> E2, TF-down -> E3
//============================================================================
`timescale 1ns/1ps
`include "bisr_defines.vh"

module tb_march;

    localparam N_MEM = 2, ROWS = 16, WIDTH = 8;
    localparam ADDR_W = $clog2(ROWS), MEM_W = 1;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0, start = 1'b0;

    wire                   busy, done;
    wire [MEM_W-1:0]       mem_sel;
    wire [ADDR_W-1:0]      addr;
    wire                   we, re;
    wire [WIDTH-1:0]       wdata;
    wire [N_MEM*WIDTH-1:0] rdata_bus;
    wire                   fail_valid, fail_exp;
    wire [MEM_W-1:0]       fail_mem;
    wire [ADDR_W-1:0]      fail_row;
    wire [WIDTH-1:0]       fail_bits;
    wire [2:0]             fail_elem;

    march_cminus #(.N_MEM (N_MEM), .ROWS (ROWS), .WIDTH (WIDTH)) dut (
        .clk (clk), .rst_n (rst_n), .start (start), .busy (busy), .done (done),
        .mem_sel (mem_sel), .addr (addr), .we (we), .re (re), .wdata (wdata),
        .rdata_bus (rdata_bus),
        .fail_valid (fail_valid), .fail_mem (fail_mem), .fail_row (fail_row),
        .fail_bits (fail_bits), .fail_exp (fail_exp), .fail_elem (fail_elem)
    );

    genvar g;
    generate
        for (g = 0; g < N_MEM; g = g + 1) begin : g_mem
            sram_wrapper #(
                .ROWS (ROWS), .WIDTH (WIDTH), .N_LOCAL (1), .N_GLOBAL (0),
                .ADDR_W (ADDR_W), .SIDX_W (1), .GLB (1)
            ) u_wrap (
                .clk (clk), .scan_en (1'b0),
                .addr (addr), .we (we & (mem_sel == g)), .re (re & (mem_sel == g)),
                .wdata (wdata),
                .hit (1'b0), .is_global (1'b0), .sidx (1'b0), .local_en (1'b0),
                .global_rdata ({WIDTH{1'b0}}), .g_we (),
                .rdata (rdata_bus[g*WIDTH +: WIDTH])
            );
        end
    endgenerate

    // ---------------- fail monitor ----------------
    integer n_fail, first_elem, first_mem, first_row, cycles;
    always @(posedge clk) begin
        if (fail_valid) begin
            if (n_fail == 0) begin
                first_elem = fail_elem; first_mem = fail_mem; first_row = fail_row;
            end
            n_fail = n_fail + 1;
        end
        if (we | re) cycles = cycles + 1;   // memory operations issued
    end

    task run_mbist;
        begin
            n_fail = 0; cycles = 0; first_elem = -1; first_mem = -1; first_row = -1;
            @(negedge clk) start = 1'b1;
            @(negedge clk) start = 1'b0;
            wait (done); @(negedge clk);
        end
    endtask

    integer errors = 0;

    task expect_fault(input integer mem, input integer row, input integer elem,
                      input [8*16-1:0] name);
        begin
            run_mbist;
            if (n_fail == 0 || first_mem != mem || first_row != row || first_elem != elem) begin
                errors = errors + 1;
                $display("FAIL %0s: fails=%0d first at mem%0d row%0d E%0d (expected mem%0d row%0d E%0d)",
                         name, n_fail, first_mem, first_row, first_elem, mem, row, elem);
            end else
                $display("ok   %0s: %0d fail(s), first at mem%0d row%0d E%0d",
                         name, n_fail, first_mem, first_row, first_elem);
        end
    endtask

    task clear_all;
        begin
            g_mem[0].u_wrap.u_fi.clear_faults;
            g_mem[1].u_wrap.u_fi.clear_faults;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // fault-free
        run_mbist;
        // March C- = 10 operations per row, one memory after the other
        if (n_fail != 0 || cycles != 10*ROWS*N_MEM) begin
            errors = errors + 1;
            $display("FAIL fault-free: fails=%0d operations=%0d (expected 0, %0d)",
                     n_fail, cycles, 10*ROWS*N_MEM);
        end else
            $display("ok   fault-free: 0 fails, %0d operations", cycles);

        clear_all; g_mem[1].u_wrap.u_fi.add_fault(9, 1, `FT_SA1);
        expect_fault(1, 9, 1, "SA1");

        clear_all; g_mem[0].u_wrap.u_fi.add_fault(2, 4, `FT_SA0);
        expect_fault(0, 2, 2, "SA0");

        clear_all; g_mem[0].u_wrap.u_fi.add_fault(5, 6, `FT_TF_UP);
        expect_fault(0, 5, 2, "TF-up");

        clear_all; g_mem[1].u_wrap.u_fi.add_fault(15, 0, `FT_TF_DOWN);
        expect_fault(1, 15, 3, "TF-down");

        if (errors == 0) $display("TB_MARCH: ALL CHECKS PASSED");
        else             $display("TB_MARCH: %0d CHECK(S) FAILED", errors);
        $finish;
    end

endmodule
