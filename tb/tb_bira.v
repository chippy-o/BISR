//============================================================================
// tb_bira.v
// Unit test: bira writing into the spare-indexed repair_table
// (N_MEM = 2, 1 local, 2 global).
//
// The fault table is driven directly by the testbench.
//   Case A (S2): mem0 row10, mem1 row200     -> local, local
//   Case B (S3): mem0 rows 5, 100, 250       -> local, global0, global1
//   Case C (S4): mem0 rows 1, 2, 3, 4        -> unrepairable
//   Case D    : overflow flag, empty table   -> unrepairable
//============================================================================
`timescale 1ns/1ps

module tb_bira;

    localparam N_MEM = 2, FT = 8, N_LOCAL = 1, N_GLOBAL = 2;
    localparam MEM_W = 1, ADDR_W = 8, SIDX_W = 1, LCNT_W = 1, GCNT_W = 2, FIDX_W = 3;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0, start = 1'b0, clear = 1'b0;

    reg  [FT-1:0]        ft_valid;
    reg  [FT*MEM_W-1:0]  ft_mem;
    reg  [FT*ADDR_W-1:0] ft_row;
    reg                  ft_overflow;

    wire              busy, done, rt_we, rt_valid, rt_is_global, unrep;
    wire [FIDX_W-1:0] rt_idx;
    wire [MEM_W-1:0]  rt_mem;
    wire [ADDR_W-1:0] rt_row;
    wire [SIDX_W-1:0] rt_sidx;
    wire [N_MEM*LCNT_W-1:0] local_used;
    wire [GCNT_W-1:0] global_used;

    bira #(
        .N_MEM (N_MEM), .FT_DEPTH (FT), .N_LOCAL (N_LOCAL), .N_GLOBAL (N_GLOBAL),
        .MEM_W (MEM_W), .ADDR_W (ADDR_W), .SIDX_W (SIDX_W),
        .LCNT_W (LCNT_W), .GCNT_W (GCNT_W), .FIDX_W (FIDX_W)
    ) dut (
        .clk (clk), .rst_n (rst_n), .start (start),
        .ft_valid (ft_valid), .ft_mem (ft_mem), .ft_row (ft_row), .ft_overflow (ft_overflow),
        .busy (busy), .done (done),
        .rt_we (rt_we), .rt_idx (rt_idx), .rt_valid (rt_valid), .rt_mem (rt_mem),
        .rt_row (rt_row), .rt_is_global (rt_is_global), .rt_sidx (rt_sidx),
        .unrepairable (unrep), .local_used (local_used), .global_used (global_used)
    );

    wire [N_MEM*N_LOCAL-1:0]        lt_valid;
    wire [N_MEM*N_LOCAL*ADDR_W-1:0] lt_row;
    wire [N_GLOBAL-1:0]             gt_valid;
    wire [N_GLOBAL*MEM_W-1:0]       gt_mem;
    wire [N_GLOBAL*ADDR_W-1:0]      gt_row;

    repair_table #(
        .N_MEM (N_MEM), .N_LOCAL (N_LOCAL), .N_GLOBAL (N_GLOBAL),
        .MEM_W (MEM_W), .ADDR_W (ADDR_W), .SIDX_W (SIDX_W)
    ) u_rt (
        .clk (clk), .rst_n (rst_n), .clear (clear),
        .we (rt_we), .w_valid (rt_valid), .w_mem (rt_mem),
        .w_row (rt_row), .w_is_global (rt_is_global), .w_sidx (rt_sidx),
        .lt_valid (lt_valid), .lt_row (lt_row),
        .gt_valid (gt_valid), .gt_mem (gt_mem), .gt_row (gt_row)
    );

    integer n;
    task load_clear;
        begin ft_valid = 0; ft_mem = 0; ft_row = 0; ft_overflow = 0; n = 0; end
    endtask
    task add(input integer m, input integer r);
        begin
            ft_valid[n] = 1'b1; ft_mem[n*MEM_W +: MEM_W] = m; ft_row[n*ADDR_W +: ADDR_W] = r;
            n = n + 1;
        end
    endtask
    task run;
        begin
            @(negedge clk) clear = 1'b1;
            @(negedge clk) clear = 1'b0; start = 1'b1;
            @(negedge clk) start = 1'b0;
            wait (done); @(negedge clk);
        end
    endtask

    integer errors = 0;
    task check(input cond, input [8*48-1:0] what);
        begin
            if (!cond) begin errors = errors + 1; $display("FAIL %0s", what); end
            else $display("ok   %0s", what);
        end
    endtask

    function [ADDR_W-1:0] lrow(input integer slot); lrow = lt_row[slot*ADDR_W +: ADDR_W]; endfunction
    function [ADDR_W-1:0] grow(input integer slot); grow = gt_row[slot*ADDR_W +: ADDR_W]; endfunction

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // Case A
        load_clear; add(0, 10); add(1, 200); run;
        check(!unrep && local_used == 2'b11 && global_used == 0, "A: 1 local each, no global");
        check(lt_valid == 2'b11 && gt_valid == 0 && lrow(0) == 10 && lrow(1) == 200,
              "A: local slots mem0=10, mem1=200");

        // Case B
        load_clear; add(0, 5); add(0, 100); add(0, 250); run;
        check(!unrep && local_used == 2'b01 && global_used == 2, "B: local + 2 global");
        check(lt_valid == 2'b01 && lrow(0) == 5 && gt_valid == 2'b11 && gt_mem == 2'b00 &&
              grow(0) == 100 && grow(1) == 250, "B: local0=5, global0=100, global1=250 (mem0)");

        // Case C
        load_clear; add(0, 1); add(0, 2); add(0, 3); add(0, 4); run;
        check(unrep && global_used == 2, "C: 4 rows -> unrepairable");
        check(lt_valid == 2'b01 && lrow(0) == 1 && grow(0) == 2 && grow(1) == 3,
              "C: rows 1,2,3 repaired, row 4 left without a spare");

        // Case D
        load_clear; ft_overflow = 1'b1; run;
        check(unrep, "D: overflow -> unrepairable");

        if (errors == 0) $display("TB_BIRA: ALL CHECKS PASSED");
        else             $display("TB_BIRA: %0d CHECK(S) FAILED", errors);
        $finish;
    end

endmodule
