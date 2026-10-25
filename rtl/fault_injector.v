//============================================================================
// fault_injector.v   (SIMULATION ONLY - not synthesisable)
//
// Sits between a storage element and its port and makes chosen cells
// misbehave. Used on the main arrays and on every spare row, so faults can be
// placed anywhere in the memory system.
//
//      port wdata --> [wdata_in  -> wdata_out] --> storage
//      port rdata <-- [rdata_out <- cur_data ] <-- storage
//
// Supported fault models (codes in bisr_defines.vh):
//   FT_SA0     : bit forced to 0 on both write and read
//   FT_SA1     : bit forced to 1 on both write and read
//   FT_TF_UP   : a write that would take the bit 0 -> 1 leaves it at 0
//   FT_TF_DOWN : a write that would take the bit 1 -> 0 leaves it at 1
//
// The fault list is loaded by the testbench through hierarchical task calls:
//   <path>.u_fi.add_fault(row, bit, type);
//   <path>.u_fi.clear_faults;
//
// Instantiation is guarded by `ifdef FAULT_INJECT in sram_wrapper and
// spare_row_bank, so synthesis never sees this module.
//============================================================================
`timescale 1ns/1ps
`default_nettype none
`include "bisr_defines.vh"

module fault_injector #(
    parameter ROWS   = 256,
    parameter WIDTH  = 8,
    parameter NF     = 32,                        // max faults per instance
    parameter ADDR_W = (ROWS > 1) ? $clog2(ROWS) : 1
)(
    input  wire [ADDR_W-1:0] addr,       // row being accessed
    input  wire [WIDTH-1:0]  wdata_in,   // data the port wants to write
    input  wire [WIDTH-1:0]  cur_data,   // data currently stored at addr
    output reg  [WIDTH-1:0]  wdata_out,  // data actually written to storage
    output reg  [WIDTH-1:0]  rdata_out   // data the port sees on a read
);

    // ------------------------------------------------------------------
    // Fault table
    // ------------------------------------------------------------------
    reg     f_valid [0:NF-1];
    integer f_row   [0:NF-1];
    integer f_bit   [0:NF-1];
    integer f_type  [0:NF-1];
    integer n_faults;
    reg [31:0] f_gen;      // bumped on every table change -> re-evaluate logic

    integer i;
    initial begin
        n_faults = 0;
        f_gen    = 0;
        for (i = 0; i < NF; i = i + 1) f_valid[i] = 1'b0;
    end

    // Add one faulty cell
    task add_fault(input integer row, input integer bitpos, input integer ftype);
        begin
            if (n_faults >= NF)
                $display("[%0t] %m: fault table full, fault ignored", $time);
            else if (row < 0 || row >= ROWS || bitpos < 0 || bitpos >= WIDTH)
                $display("[%0t] %m: fault (row %0d, bit %0d) out of range, ignored",
                         $time, row, bitpos);
            else begin
                f_valid[n_faults] = 1'b1;
                f_row  [n_faults] = row;
                f_bit  [n_faults] = bitpos;
                f_type [n_faults] = ftype;
                n_faults = n_faults + 1;
                f_gen    = f_gen + 1;
            end
        end
    endtask

    // Remove all faults
    task clear_faults;
        begin
            for (i = 0; i < NF; i = i + 1) f_valid[i] = 1'b0;
            n_faults = 0;
            f_gen    = f_gen + 1;
        end
    endtask

    // ------------------------------------------------------------------
    // Fault behaviour (explicit sensitivity list: arrays are not
    // reliably covered by @* in every simulator)
    // ------------------------------------------------------------------
    integer j, b;
    always @(addr or wdata_in or cur_data or f_gen) begin
        wdata_out = wdata_in;
        rdata_out = cur_data;
        for (j = 0; j < NF; j = j + 1) begin
            if (f_valid[j] && (f_row[j] == addr)) begin
                b = f_bit[j];
                case (f_type[j])
                    `FT_SA0: begin
                        wdata_out[b] = 1'b0;
                        rdata_out[b] = 1'b0;
                    end
                    `FT_SA1: begin
                        wdata_out[b] = 1'b1;
                        rdata_out[b] = 1'b1;
                    end
                    `FT_TF_UP: begin
                        // 0 -> 1 write is lost: cell keeps 0
                        if (cur_data[b] === 1'b0 && wdata_in[b] === 1'b1)
                            wdata_out[b] = 1'b0;
                    end
                    `FT_TF_DOWN: begin
                        // 1 -> 0 write is lost: cell keeps 1
                        if (cur_data[b] === 1'b1 && wdata_in[b] === 1'b0)
                            wdata_out[b] = 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule

`default_nettype wire
