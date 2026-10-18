//============================================================================
// bisr_ctrl_fsm.v
// Top-level BISR sequencer.
//
//   IDLE --start--> CLEAR --> TEST --mbist_done--> ANALYZE --bira_done-->
//        +-- unrepairable --------------------------------------> DONE (fail)
//        +-- else --> LOAD --> VERIFY --mbist_done--> DONE (pass / fail)
//
//   CLEAR   : empty fault table + repair table, start MBIST
//   TEST    : March C- on the raw arrays, fails are logged
//   ANALYZE : BIRA allocates spares, writes the repair table
//   LOAD    : remapping switched on, start MBIST again
//   VERIFY  : March C- through the remap logic; any fail = repair failed
//   DONE    : result held; memories usable with the repair applied
//
// bisr_start can be pulsed again from DONE (or IDLE) to re-run everything.
//============================================================================
`timescale 1ns/1ps
`default_nettype none

module bisr_ctrl_fsm (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,          // 1-cycle pulse

    input  wire       mbist_done,     // from march_cminus
    input  wire       bira_done,      // from bira
    input  wire       bira_unrep,     // from bira
    input  wire       fail_valid,     // from march_cminus

    output wire       clear,          // clear fault + repair tables
    output wire       mbist_start,
    output wire       bira_start,
    output wire       log_en,         // log fails (TEST only)
    output wire       remap_en,       // use the repair table
    output wire       bist_mode,      // MBIST owns the memory ports

    output wire       busy,
    output wire       done,
    output wire       pass,
    output reg        unrepairable,
    output reg        verify_fail,
    output reg  [2:0] state
);

    localparam [2:0] S_IDLE    = 3'd0,
                     S_CLEAR   = 3'd1,
                     S_TEST    = 3'd2,
                     S_ANALYZE = 3'd3,
                     S_LOAD    = 3'd4,
                     S_VERIFY  = 3'd5,
                     S_DONE    = 3'd6;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            unrepairable <= 1'b0;
            verify_fail  <= 1'b0;
        end else begin
            case (state)
                S_IDLE, S_DONE: begin
                    if (start) state <= S_CLEAR;
                end

                S_CLEAR: begin
                    unrepairable <= 1'b0;
                    verify_fail  <= 1'b0;
                    state        <= S_TEST;
                end

                S_TEST: begin
                    if (mbist_done) state <= S_ANALYZE;
                end

                S_ANALYZE: begin
                    if (bira_done) begin
                        unrepairable <= bira_unrep;
                        state        <= bira_unrep ? S_DONE : S_LOAD;
                    end
                end

                S_LOAD: state <= S_VERIFY;

                S_VERIFY: begin
                    if (fail_valid) verify_fail <= 1'b1;
                    if (mbist_done) state <= S_DONE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign clear       = (state == S_CLEAR);
    assign mbist_start = (state == S_CLEAR) | (state == S_LOAD);
    assign bira_start  = (state == S_TEST) & mbist_done;
    assign log_en      = (state == S_TEST);
    assign remap_en    = (state == S_LOAD) | (state == S_VERIFY) | (state == S_DONE);
    assign bist_mode   = (state == S_TEST) | (state == S_VERIFY);

    assign busy = (state != S_IDLE) & (state != S_DONE);
    assign done = (state == S_DONE);
    assign pass = (state == S_DONE) & ~unrepairable & ~verify_fail;

endmodule

`default_nettype wire
