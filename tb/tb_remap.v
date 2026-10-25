//============================================================================
// tb_remap.v
// Unit test: remap_unit fed by the spare-indexed repair_table
// (N_MEM = 2, 1 local, 2 global).
//
// Repair table loaded with:
//   mem0 row5   -> local  spare 0 of mem0
//   mem0 row100 -> global spare 0
//   mem1 row5   -> global spare 1
// Checks hits / steering for several addresses, spare enables, and that
// remap_en = 0 disables everything.
//============================================================================
`timescale 1ns/1ps

module tb_remap;

    localparam N_MEM = 2, N_LOCAL = 1, N_GLOBAL = 2;
    localparam MEM_W = 1, ADDR_W = 8, SIDX_W = 1;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;

    reg               we = 0, w_valid = 0, w_is_global = 0;
    reg  [MEM_W-1:0]  w_mem = 0;
    reg  [ADDR_W-1:0] w_row = 0;
    reg  [SIDX_W-1:0] w_sidx = 0;

    wire [N_MEM*N_LOCAL-1:0]        lt_valid;
    wire [N_MEM*N_LOCAL*ADDR_W-1:0] lt_row;
    wire [N_GLOBAL-1:0]             gt_valid;
    wire [N_GLOBAL*MEM_W-1:0]       gt_mem;
    wire [N_GLOBAL*ADDR_W-1:0]      gt_row;

    repair_table #(
        .N_MEM (N_MEM), .N_LOCAL (N_LOCAL), .N_GLOBAL (N_GLOBAL),
        .MEM_W (MEM_W), .ADDR_W (ADDR_W), .SIDX_W (SIDX_W)
    ) u_rt (
        .clk (clk), .rst_n (rst_n), .clear (1'b0),
        .we (we), .w_valid (w_valid), .w_mem (w_mem), .w_row (w_row),
        .w_is_global (w_is_global), .w_sidx (w_sidx),
        .lt_valid (lt_valid), .lt_row (lt_row),
        .gt_valid (gt_valid), .gt_mem (gt_mem), .gt_row (gt_row)
    );

    reg                      remap_en = 1'b1;
    reg  [N_MEM*ADDR_W-1:0]  acc_addr = 0;
    wire [N_MEM-1:0]         hit, is_global;
    wire [N_MEM*SIDX_W-1:0]  sidx;
    wire [N_MEM*N_LOCAL-1:0] local_en;
    wire [N_GLOBAL-1:0]      global_en;

    remap_unit #(
        .N_MEM (N_MEM), .N_LOCAL (N_LOCAL), .N_GLOBAL (N_GLOBAL),
        .MEM_W (MEM_W), .ADDR_W (ADDR_W), .SIDX_W (SIDX_W), .GLB (N_GLOBAL)
    ) dut (
        .remap_en (remap_en), .acc_addr (acc_addr),
        .lt_valid (lt_valid), .lt_row (lt_row),
        .gt_valid (gt_valid), .gt_mem (gt_mem), .gt_row (gt_row),
        .hit (hit), .is_global (is_global), .sidx (sidx),
        .local_en (local_en), .global_en (global_en)
    );

    // memory m, row r -> local (g = 0) or global (g = 1) spare s
    task put(input integer m, input integer r, input g, input integer s);
        begin
            @(negedge clk);
            we = 1'b1; w_valid = 1'b1; w_mem = m; w_row = r; w_is_global = g; w_sidx = s;
            @(negedge clk); we = 1'b0;
        end
    endtask

    integer errors = 0;
    task check(input cond, input [8*48-1:0] what);
        begin
            if (!cond) begin errors = errors + 1; $display("FAIL %0s", what); end
            else $display("ok   %0s", what);
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        put(0, 5,   1'b0, 0);
        put(0, 100, 1'b1, 0);
        put(1, 5,   1'b1, 1);

        // a write with w_valid = 0 must not touch the table
        @(negedge clk); we = 1'b1; w_valid = 1'b0; w_mem = 1; w_row = 77; w_is_global = 1'b0; w_sidx = 0;
        @(negedge clk); we = 1'b0;
        check(lt_valid == 2'b01, "w_valid=0 write ignored");

        // mem0 @5 (local 0), mem1 @5 (global 1)
        acc_addr = {8'd5, 8'd5}; #1;
        check(hit == 2'b11,                          "both memories hit at row 5");
        check(is_global == 2'b10 && sidx == 2'b10,   "mem0->local0, mem1->global1");

        // mem0 @100 (global 0), mem1 @100 (miss)
        acc_addr = {8'd100, 8'd100}; #1;
        check(hit == 2'b01 && is_global[0] && sidx[0] == 1'b0, "mem0 row100 -> global0, mem1 miss");

        // misses
        acc_addr = {8'd6, 8'd6}; #1;
        check(hit == 2'b00,                          "row 6 misses on both");

        // spare enables
        check(local_en == 2'b01 && global_en == 2'b11, "enables: local mem0 only, both globals");

        // disable remapping
        remap_en = 1'b0; acc_addr = {8'd5, 8'd5}; #1;
        check(hit == 0 && local_en == 0 && global_en == 0, "remap_en=0 disables all");

        if (errors == 0) $display("TB_REMAP: ALL CHECKS PASSED");
        else             $display("TB_REMAP: %0d CHECK(S) FAILED", errors);
        $finish;
    end

endmodule
