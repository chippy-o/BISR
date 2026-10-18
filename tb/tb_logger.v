//============================================================================
// tb_logger.v
// Unit test: fault_logger.
//
// Checks
//   * two fails on the same row merge into one entry (mask and class OR-ed)
//   * new rows take the next entry
//   * a new row with the table full raises overflow; a fail on an already
//     logged row is still merged when full
//   * log_en = 0 ignores fails; clear empties the table
//============================================================================
`timescale 1ns/1ps

module tb_logger;

    localparam FT = 4, MEM_W = 1, ADDR_W = 8, WIDTH = 8;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg               rst_n = 1'b0, clear = 1'b0, log_en = 1'b1, fail_valid = 1'b0;
    reg [MEM_W-1:0]   fail_mem = 0;
    reg [ADDR_W-1:0]  fail_row = 0;
    reg [WIDTH-1:0]   fail_bits = 0;
    reg               fail_exp = 0;

    wire [FT-1:0]        ft_valid;
    wire [FT*MEM_W-1:0]  ft_mem;
    wire [FT*ADDR_W-1:0] ft_row;
    wire [FT*WIDTH-1:0]  ft_mask;
    wire [FT*2-1:0]      ft_class;
    wire                 overflow;
    wire [2:0]           count;

    fault_logger #(.FT_DEPTH (FT), .MEM_W (MEM_W), .ADDR_W (ADDR_W), .WIDTH (WIDTH)) dut (
        .clk (clk), .rst_n (rst_n), .clear (clear), .log_en (log_en),
        .fail_valid (fail_valid), .fail_mem (fail_mem), .fail_row (fail_row),
        .fail_bits (fail_bits), .fail_exp (fail_exp),
        .ft_valid (ft_valid), .ft_mem (ft_mem), .ft_row (ft_row),
        .ft_mask (ft_mask), .ft_class (ft_class),
        .overflow (overflow), .count (count)
    );

    task fail(input integer m, input integer r, input [WIDTH-1:0] bits, input e);
        begin
            @(negedge clk);
            fail_valid = 1'b1; fail_mem = m; fail_row = r; fail_bits = bits; fail_exp = e;
            @(negedge clk);
            fail_valid = 1'b0;
        end
    endtask

    integer errors = 0;
    task check(input cond, input [8*40-1:0] what);
        begin
            if (!cond) begin errors = errors + 1; $display("FAIL %0s", what); end
            else $display("ok   %0s", what);
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        fail(0, 10, 8'h01, 1'b0);          // mem0 row10 bit0, read 1 expected 0
        fail(0, 10, 8'h10, 1'b1);          // same row, bit4, read 0 expected 1
        check(count == 1,                    "merge: still 1 entry");
        check(ft_mask[7:0] == 8'h11,         "merge: mask ORed = 11");
        check(ft_class[1:0] == 2'b11,        "merge: class ORed = 11");

        fail(1, 10, 8'h80, 1'b1);          // mem1 row10 -> different entry
        fail(0, 20, 8'h02, 1'b0);
        fail(1, 30, 8'h04, 1'b0);
        check(count == 4 && !overflow,       "4 distinct rows, no overflow");
        check(ft_mem[1] == 1'b1 && ft_row[15:8] == 8'd10, "entry1 = mem1 row10");

        fail(0, 20, 8'h40, 1'b1);          // already logged row while full
        check(!overflow && ft_mask[23:16] == 8'h42, "merge while full, no overflow");

        fail(0, 99, 8'h01, 1'b0);          // new row, table full
        check(overflow,                      "new row when full -> overflow");

        log_en = 1'b0;
        @(negedge clk) clear = 1'b1;
        @(negedge clk) clear = 1'b0;
        fail(0, 5, 8'h01, 1'b0);
        check(count == 0 && !overflow && ft_valid == 0, "clear + log_en=0 ignores fail");

        if (errors == 0) $display("TB_LOGGER: ALL CHECKS PASSED");
        else             $display("TB_LOGGER: %0d CHECK(S) FAILED", errors);
        $finish;
    end

endmodule
