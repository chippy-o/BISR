//============================================================================
// tb_top_scenarios.v
// System test for shared_bisr_top (ARCH = 0) or dedicated_bisr_top
// (ARCH = 1), with a built-in reference model of the repair algorithm.
//
// For every run the testbench:
//   1. injects faults (main rows, local spares, global spares)
//   2. computes the EXPECTED outcome with a behavioural model of
//      "local first, then global, else unrepairable" (+ table overflow and
//      faulty assigned spares)
//   3. runs the BISR and compares pass / unrepairable / overflow /
//      verify_fail / fault count / spares used against the model
//   4. if the repair passed, writes and reads every row of every memory
//      through the functional ports (checks the remap in normal operation)
//   5. prints a machine-readable RESULT line (for the Python scripts)
//
// Modes (plusargs)
//   (none)              directed scenarios S1..S8
//   +RANDOM=<n>         n random fault sets   (+SEED=<s> optional)
//   +FAULTFILE=<path>   one run with faults read from a file, one per line:
//                         <target> <mem> <spare> <row> <bit> <type>
//                       target: 0 main, 1 local spare, 2 global spare
//                       type  : 0 SA0, 1 SA1, 2 TF-up, 3 TF-down
//
// Parameters: ARCH, N_MEM, ROWS, WIDTH, N_LOCAL, N_GLOBAL, FT_DEPTH, SPARE_GATING
//============================================================================
`timescale 1ns/1ps
`include "bisr_defines.vh"

module tb_top_scenarios;

    parameter ARCH         = 0;      // 0 = shared (proposed), 1 = dedicated
    parameter N_MEM        = 2;
    parameter ROWS         = 256;
    parameter WIDTH        = 8;
    parameter N_LOCAL      = 1;
    parameter N_GLOBAL     = 2;      // ignored when ARCH = 1
    parameter FT_DEPTH     = 8;
    parameter SPARE_GATING = 1;

    localparam ADDR_W  = $clog2(ROWS);
    localparam LCNT_W  = $clog2(N_LOCAL + 1);
    localparam NG      = (ARCH == 0) ? N_GLOBAL : 0;    // global spares present
    localparam NGA     = (NG > 0) ? NG : 1;             // array size helper
    localparam MAXF    = 64;                            // reference-model capacity
    localparam TIMEOUT = 40 * ROWS * N_MEM + 1000;      // cycles per BISR run

    // ------------------------------------------------------------------
    // Clock, reset, DUT signals
    // ------------------------------------------------------------------
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0, scan_en = 1'b0, bisr_start = 1'b0;

    wire                    busy, done, pass, unrep, ovf, vfail;
    wire [15:0]             fcnt;
    wire [N_MEM*LCNT_W-1:0] lused;
    wire [7:0]              gused;

    reg  [N_MEM*ADDR_W-1:0] f_addr  = 0;
    reg  [N_MEM-1:0]        f_we    = 0, f_re = 0;
    reg  [N_MEM*WIDTH-1:0]  f_wdata = 0;
    wire [N_MEM*WIDTH-1:0]  f_rdata;

    generate
        if (ARCH == 0) begin : g_dut
            shared_bisr_top #(
                .N_MEM (N_MEM), .ROWS (ROWS), .WIDTH (WIDTH), .N_LOCAL (N_LOCAL),
                .N_GLOBAL (N_GLOBAL), .FT_DEPTH (FT_DEPTH), .SPARE_GATING (SPARE_GATING)
            ) dut (
                .clk (clk), .rst_n (rst_n), .scan_en (scan_en), .bisr_start (bisr_start),
                .bisr_busy (busy), .bisr_done (done), .bisr_pass (pass),
                .bisr_unrepairable (unrep), .bisr_overflow (ovf), .bisr_verify_fail (vfail),
                .bisr_fault_count (fcnt), .bisr_local_used (lused), .bisr_global_used (gused),
                .func_addr (f_addr), .func_we (f_we), .func_re (f_re),
                .func_wdata (f_wdata), .func_rdata (f_rdata)
            );
        end else begin : g_dut
            dedicated_bisr_top #(
                .N_MEM (N_MEM), .ROWS (ROWS), .WIDTH (WIDTH), .N_LOCAL (N_LOCAL),
                .FT_DEPTH (FT_DEPTH), .SPARE_GATING (SPARE_GATING)
            ) dut (
                .clk (clk), .rst_n (rst_n), .scan_en (scan_en), .bisr_start (bisr_start),
                .bisr_busy (busy), .bisr_done (done), .bisr_pass (pass),
                .bisr_unrepairable (unrep), .bisr_overflow (ovf), .bisr_verify_fail (vfail),
                .bisr_fault_count (fcnt), .bisr_local_used (lused), .bisr_global_used (gused),
                .func_addr (f_addr), .func_we (f_we), .func_re (f_re),
                .func_wdata (f_wdata), .func_rdata (f_rdata)
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // Fault-injection plumbing
    // The `inject` task sets inj_* and fires inj_ev; the generate blocks
    // below forward the fault to the matching fault_injector instance.
    // ------------------------------------------------------------------
    integer inj_tgt, inj_mem, inj_spare, inj_row, inj_bit, inj_type;
    event   inj_ev, clr_ev;

    genvar g, k;
    generate
        if (ARCH == 0) begin : g_fi_shared
            for (g = 0; g < N_MEM; g = g + 1) begin : g_m
                always @(inj_ev)
                    if (inj_tgt == `TGT_MAIN && inj_mem == g)
                        g_dut.dut.g_mem[g].u_wrap.u_fi.add_fault(inj_row, inj_bit, inj_type);
                always @(clr_ev)
                    g_dut.dut.g_mem[g].u_wrap.u_fi.clear_faults;
                for (k = 0; k < N_LOCAL; k = k + 1) begin : g_l
                    always @(inj_ev)
                        if (inj_tgt == `TGT_LOCAL && inj_mem == g && inj_spare == k)
                            g_dut.dut.g_mem[g].u_wrap.u_local.g_row[k].u_fi.add_fault(0, inj_bit, inj_type);
                    always @(clr_ev)
                        g_dut.dut.g_mem[g].u_wrap.u_local.g_row[k].u_fi.clear_faults;
                end
            end
            if (N_GLOBAL > 0) begin : g_gp
                for (k = 0; k < N_GLOBAL; k = k + 1) begin : g_g
                    always @(inj_ev)
                        if (inj_tgt == `TGT_GLOBAL && inj_spare == k)
                            g_dut.dut.g_glb.u_pool.g_row[k].u_fi.add_fault(0, inj_bit, inj_type);
                    always @(clr_ev)
                        g_dut.dut.g_glb.u_pool.g_row[k].u_fi.clear_faults;
                end
            end
        end else begin : g_fi_dedicated
            for (g = 0; g < N_MEM; g = g + 1) begin : g_m
                always @(inj_ev)
                    if (inj_tgt == `TGT_MAIN && inj_mem == g)
                        g_dut.dut.g_inst[g].u_bisr.g_mem[0].u_wrap.u_fi.add_fault(inj_row, inj_bit, inj_type);
                always @(clr_ev)
                    g_dut.dut.g_inst[g].u_bisr.g_mem[0].u_wrap.u_fi.clear_faults;
                for (k = 0; k < N_LOCAL; k = k + 1) begin : g_l
                    always @(inj_ev)
                        if (inj_tgt == `TGT_LOCAL && inj_mem == g && inj_spare == k)
                            g_dut.dut.g_inst[g].u_bisr.g_mem[0].u_wrap.u_local.g_row[k].u_fi.add_fault(0, inj_bit, inj_type);
                    always @(clr_ev)
                        g_dut.dut.g_inst[g].u_bisr.g_mem[0].u_wrap.u_local.g_row[k].u_fi.clear_faults;
                end
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // Reference model state
    // ------------------------------------------------------------------
    integer rf_n;                               // main-array faults injected
    integer rf_mem [0:MAXF-1];
    integer rf_row [0:MAXF-1];
    reg     rf_lsp [0:N_MEM*N_LOCAL-1];         // local spare (m,k) faulty
    reg     rf_gsp [0:NGA-1];                   // global spare k faulty

    integer i_tmp;

    task clear_faults;
        begin
            -> clr_ev; #1;
            rf_n = 0;
            for (i_tmp = 0; i_tmp < N_MEM*N_LOCAL; i_tmp = i_tmp + 1) rf_lsp[i_tmp] = 1'b0;
            for (i_tmp = 0; i_tmp < NGA; i_tmp = i_tmp + 1)           rf_gsp[i_tmp] = 1'b0;
        end
    endtask

    // target, memory, spare index, row, bit, fault type
    task inject(input integer tgt, input integer mem, input integer spare,
                input integer row, input integer bitp, input integer ftype);
        begin
            inj_tgt = tgt; inj_mem = mem; inj_spare = spare;
            inj_row = row; inj_bit = bitp; inj_type = ftype;
            -> inj_ev; #1;
            if (tgt == `TGT_MAIN) begin
                if (rf_n < MAXF) begin
                    rf_mem[rf_n] = mem; rf_row[rf_n] = row; rf_n = rf_n + 1;
                end
            end else if (tgt == `TGT_LOCAL) begin
                rf_lsp[mem*N_LOCAL + spare] = 1'b1;
            end else if (tgt == `TGT_GLOBAL && NG > 0) begin
                rf_gsp[spare] = 1'b1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Reference model: expected outcome of the BISR
    // ------------------------------------------------------------------
    integer e_pass, e_unrep, e_ovf, e_vfail, e_fcnt, e_gused;
    integer e_lused [0:N_MEM-1];
    integer rows_m  [0:N_MEM-1];

    function integer imin(input integer a, input integer b);
        imin = (a < b) ? a : b;
    endfunction

    task compute_expected;
        integer i, j, m, kk, dup, distinct, excess, ovf_m, unrep_m;
        begin
            for (m = 0; m < N_MEM; m = m + 1) rows_m[m] = 0;
            distinct = 0;
            // count distinct faulty rows per memory
            for (i = 0; i < rf_n; i = i + 1) begin
                dup = 0;
                for (j = 0; j < i; j = j + 1)
                    if (rf_mem[j] == rf_mem[i] && rf_row[j] == rf_row[i]) dup = 1;
                if (!dup) begin
                    rows_m[rf_mem[i]] = rows_m[rf_mem[i]] + 1;
                    distinct = distinct + 1;
                end
            end

            e_vfail = 0; e_ovf = 0; e_unrep = 0; e_fcnt = 0; e_gused = 0;

            if (ARCH == 0) begin
                // shared: one table, local spares first, then the global pool
                e_ovf  = (distinct > FT_DEPTH);
                e_fcnt = imin(distinct, FT_DEPTH);
                excess = 0;
                for (m = 0; m < N_MEM; m = m + 1) begin
                    e_lused[m] = imin(rows_m[m], N_LOCAL);
                    excess     = excess + rows_m[m] - e_lused[m];
                end
                e_gused = imin(excess, NG);
                e_unrep = e_ovf || (excess > NG);
                if (!e_unrep) begin
                    // an assigned spare that is itself faulty fails VERIFY
                    for (m = 0; m < N_MEM; m = m + 1)
                        for (kk = 0; kk < e_lused[m]; kk = kk + 1)
                            if (rf_lsp[m*N_LOCAL + kk]) e_vfail = 1;
                    for (kk = 0; kk < e_gused; kk = kk + 1)
                        if (rf_gsp[kk]) e_vfail = 1;
                end
            end else begin
                // dedicated: every memory on its own, local spares only
                for (m = 0; m < N_MEM; m = m + 1) begin
                    ovf_m      = (rows_m[m] > FT_DEPTH);
                    unrep_m    = ovf_m || (rows_m[m] > N_LOCAL);
                    e_lused[m] = imin(rows_m[m], N_LOCAL);
                    e_fcnt     = e_fcnt + imin(rows_m[m], FT_DEPTH);
                    if (ovf_m)   e_ovf   = 1;
                    if (unrep_m) e_unrep = 1;
                    if (!unrep_m)
                        for (kk = 0; kk < e_lused[m]; kk = kk + 1)
                            if (rf_lsp[m*N_LOCAL + kk]) e_vfail = 1;
                end
            end
            e_pass = !e_unrep && !e_vfail;
        end
    endtask

    // ------------------------------------------------------------------
    // Functional check after a successful repair: every row of every
    // memory must store and return its own data pattern.
    // ------------------------------------------------------------------
    function [WIDTH-1:0] pattern(input integer m, input integer r);
        pattern = r * 7 + m * 31 + 8'h5A;
    endfunction

    task functional_test(output integer nerr);
        integer r, m;
        begin
            nerr = 0;
            for (r = 0; r < ROWS; r = r + 1) begin
                @(negedge clk);
                for (m = 0; m < N_MEM; m = m + 1) begin
                    f_addr [m*ADDR_W +: ADDR_W] = r;
                    f_wdata[m*WIDTH  +: WIDTH]  = pattern(m, r);
                end
                f_we = {N_MEM{1'b1}};
            end
            @(negedge clk) f_we = 0;
            for (r = 0; r < ROWS; r = r + 1) begin
                @(negedge clk);
                for (m = 0; m < N_MEM; m = m + 1) f_addr[m*ADDR_W +: ADDR_W] = r;
                f_re = {N_MEM{1'b1}};
                @(negedge clk);
                f_re = 0;
                for (m = 0; m < N_MEM; m = m + 1)
                    if (f_rdata[m*WIDTH +: WIDTH] !== pattern(m, r)) begin
                        if (nerr < 5)
                            $display("    functional mismatch mem%0d row%0d: %h != %h",
                                     m, r, f_rdata[m*WIDTH +: WIDTH], pattern(m, r));
                        nerr = nerr + 1;
                    end
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Run the BISR once and compare with the reference model
    // ------------------------------------------------------------------
    integer total_runs = 0, total_errors = 0;
    integer quiet = 0;                  // 1 = only print mismatches (random mode)

    task run_check(input [8*24-1:0] name);
        integer cyc, errs, ferr, m;
        begin
            compute_expected;
            errs = 0;

            @(negedge clk) bisr_start = 1'b1;
            @(negedge clk) bisr_start = 1'b0;
            cyc = 0;
            while (!done && cyc < TIMEOUT) begin
                @(negedge clk);
                cyc = cyc + 1;
            end
            if (!done) begin
                errs = errs + 1;
                $display("  %0s: TIMEOUT after %0d cycles", name, cyc);
            end

            if (pass  !== (e_pass  != 0)) errs = errs + 1;
            if (unrep !== (e_unrep != 0)) errs = errs + 1;
            if (ovf   !== (e_ovf   != 0)) errs = errs + 1;
            if (vfail !== (e_vfail != 0)) errs = errs + 1;
            if (fcnt  !=  e_fcnt)          errs = errs + 1;
            if (!e_ovf) begin
                if (gused != e_gused) errs = errs + 1;
                for (m = 0; m < N_MEM; m = m + 1)
                    if (lused[m*LCNT_W +: LCNT_W] != e_lused[m]) errs = errs + 1;
            end

            ferr = 0;
            if (pass === 1'b1) begin
                functional_test(ferr);
                if (ferr != 0) errs = errs + 1;
            end

            total_runs   = total_runs + 1;
            total_errors = total_errors + (errs != 0);

            if (!quiet || errs != 0) begin
                $display("%-4s %0s  pass=%0d unrep=%0d ovf=%0d vfail=%0d faults=%0d gused=%0d  (expected pass=%0d unrep=%0d ovf=%0d vfail=%0d faults=%0d gused=%0d)%0s",
                         (errs == 0) ? "ok" : "FAIL", name,
                         pass, unrep, ovf, vfail, fcnt, gused,
                         e_pass, e_unrep, e_ovf, e_vfail, e_fcnt, e_gused,
                         (pass === 1'b1) ? ((ferr == 0) ? "  functional ok" : "  FUNCTIONAL ERRORS") : "");
            end

            // machine-readable line for the Python scripts
            $write("RESULT arch=%0d n_mem=%0d n_local=%0d n_global=%0d pass=%0d unrep=%0d ovf=%0d vfail=%0d faults=%0d gused=%0d lused=",
                   ARCH, N_MEM, N_LOCAL, NG, pass, unrep, ovf, vfail, fcnt, gused);
            for (m = 0; m < N_MEM; m = m + 1)
                $write("%0d%0s", lused[m*LCNT_W +: LCNT_W], (m < N_MEM-1) ? "," : "");
            $write(" cycles=%0d match=%0d\n", cyc, (errs == 0));
        end
    endtask

    // ------------------------------------------------------------------
    // Directed scenarios
    // ------------------------------------------------------------------
    task directed;
        integer r;
        begin
            // S1: no faults
            clear_faults;
            run_check("S1 no faults");

            // S2: one faulty row in each SRAM
            clear_faults;
            inject(`TGT_MAIN, 0, 0, 10, 3, `FT_SA0);
            inject(`TGT_MAIN, 1, 0, 200 % ROWS, 7, `FT_SA1);
            run_check("S2 1 fault per SRAM");

            // S3: 3 faulty rows in SRAM0, none in SRAM1
            clear_faults;
            inject(`TGT_MAIN, 0, 0, 5,          0, `FT_SA0);
            inject(`TGT_MAIN, 0, 0, 100 % ROWS, 4, `FT_TF_UP);
            inject(`TGT_MAIN, 0, 0, 250 % ROWS, 6, `FT_TF_DOWN);
            run_check("S3 3 rows in SRAM0");

            // S4: 4 faulty rows in SRAM0
            clear_faults;
            for (r = 1; r <= 4; r = r + 1) inject(`TGT_MAIN, 0, 0, r, 0, `FT_SA1);
            run_check("S4 4 rows in SRAM0");

            // S5: several bad bits in one row
            clear_faults;
            inject(`TGT_MAIN, 0, 0, 50, 0, `FT_SA0);
            inject(`TGT_MAIN, 0, 0, 50, 1, `FT_SA1);
            inject(`TGT_MAIN, 0, 0, 50, 6, `FT_TF_UP);
            run_check("S5 3 bits, 1 row");

            // S6: the local spare that gets used is itself faulty
            clear_faults;
            inject(`TGT_MAIN,  0, 0, 20, 0, `FT_SA1);
            inject(`TGT_LOCAL, 0, 0, 0,  2, `FT_SA0);
            run_check("S6 faulty spare");

            // S7: more faulty rows than fault-table entries
            clear_faults;
            for (r = 0; r < 5; r = r + 1) inject(`TGT_MAIN, 0, 0, r, 1, `FT_SA0);
            if (N_MEM > 1)
                for (r = 0; r < 4; r = r + 1) inject(`TGT_MAIN, 1, 0, r, 1, `FT_SA0);
            run_check("S7 table overflow");

            // S8: both SRAMs need a global spare; both use them in the same
            //     cycle during the functional check
            if (N_MEM > 1) begin
                clear_faults;
                inject(`TGT_MAIN, 0, 0, 7, 2, `FT_SA0);
                inject(`TGT_MAIN, 0, 0, 9, 5, `FT_SA1);
                inject(`TGT_MAIN, 1, 0, 7, 3, `FT_TF_DOWN);
                inject(`TGT_MAIN, 1, 0, 9, 4, `FT_TF_UP);
                run_check("S8 2+2 rows");
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Random campaign
    // ------------------------------------------------------------------
    task random_runs(input integer n, input integer seed_in);
        integer it, nf, f, seed, tgt, m, s;
        begin
            seed  = seed_in;
            quiet = 1;
            for (it = 0; it < n; it = it + 1) begin
                clear_faults;
                // number of faulty rows straddles the repair capacity
                nf = {$random(seed)} % (N_MEM*N_LOCAL + NG + 3);
                for (f = 0; f < nf; f = f + 1)
                    inject(`TGT_MAIN, {$random(seed)} % N_MEM, 0,
                           {$random(seed)} % ROWS, {$random(seed)} % WIDTH,
                           {$random(seed)} % 4);
                // occasionally a faulty spare
                if ({$random(seed)} % 6 == 0) begin
                    tgt = (NG > 0 && ({$random(seed)} % 2)) ? `TGT_GLOBAL : `TGT_LOCAL;
                    m   = {$random(seed)} % N_MEM;
                    s   = (tgt == `TGT_GLOBAL) ? {$random(seed)} % NGA : {$random(seed)} % N_LOCAL;
                    inject(tgt, m, s, 0, {$random(seed)} % WIDTH, {$random(seed)} % 4);
                end
                run_check("random");
            end
            quiet = 0;
        end
    endtask

    // ------------------------------------------------------------------
    // Fault file (one run)
    // ------------------------------------------------------------------
    task file_run(input [8*256-1:0] fname);
        integer fd, cnt, t, m, s, r, b, ty;
        begin
            clear_faults;
            fd = $fopen(fname, "r");
            if (fd == 0) begin
                $display("ERROR: cannot open fault file %0s", fname);
                total_errors = total_errors + 1;
            end else begin
                cnt = $fscanf(fd, "%d %d %d %d %d %d\n", t, m, s, r, b, ty);
                while (cnt == 6) begin
                    inject(t, m, s, r, b, ty);
                    cnt = $fscanf(fd, "%d %d %d %d %d %d\n", t, m, s, r, b, ty);
                end
                $fclose(fd);
                run_check("file");
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    integer nrand, seed;
    reg [8*256-1:0] fname;

    initial begin
        if (ARCH == 0) $write("tb_top_scenarios: SHARED,");
        else           $write("tb_top_scenarios: DEDICATED,");
        $display(" N_MEM=%0d ROWS=%0d WIDTH=%0d N_LOCAL=%0d N_GLOBAL=%0d FT_DEPTH=%0d",
                 N_MEM, ROWS, WIDTH, N_LOCAL, NG, FT_DEPTH);
        clear_faults;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        if ($value$plusargs("FAULTFILE=%s", fname)) begin
            file_run(fname);
        end else if ($value$plusargs("RANDOM=%d", nrand)) begin
            if (!$value$plusargs("SEED=%d", seed)) seed = 1;
            random_runs(nrand, seed);
        end else begin
            directed;
        end

        if (total_errors == 0)
            $display("TB_TOP_SCENARIOS: ALL %0d RUN(S) MATCH THE REFERENCE MODEL", total_runs);
        else
            $display("TB_TOP_SCENARIOS: %0d of %0d RUN(S) MISMATCHED", total_errors, total_runs);
        $finish;
    end

endmodule
