//============================================================================
// tb_bisr_compare.v
// SHARED vs DEDICATED BISR - side-by-side repair verification
//
// Both designs are built for the same N_MEM SRAMs (ROWS x WIDTH each) and
// the same total number of spare rows (2 per SRAM):
//
//   DEDICATED  (dedicated_bisr_top)
//     one complete BISR per SRAM (FSM, March C-, fault logger, BIRA,
//     repair table, remap) and 2 local spare rows per SRAM.
//
//   SHARED     (clustered_bisr_top)
//     one BISR controller per group of up to 4 SRAMs. Each SRAM has 1 local
//     spare row; each controller has a global pool with 1 spare row per SRAM
//     in its group, which any SRAM of the group can borrow.
//     N_MEM <= 4 : one controller for all SRAMs
//     N_MEM  > 4 : N_MEM/4 controllers (N_MEM must be a multiple of 4)
//
// Every test
//   1. injects the same faults into both designs
//   2. runs the BISR of both designs at the same time
//   3. compares each result with the EXPECTED result from a reference
//      model of the repair rules (below)
//   4. if a design repaired, writes and reads back every row of every SRAM
//      through the normal memory ports (proves the remapping works)
//
// Reference model (what each design should do)
//   DEDICATED : SRAM m repairs iff it has <= 2 faulty rows.
//   SHARED    : per controller, faulty rows first use the SRAM's own local
//               spare; every row beyond that needs a global spare. The
//               controller repairs iff the extra rows fit in its pool and
//               the fault table did not overflow.
//   Both      : if a spare row that gets assigned is itself faulty, the
//               VERIFY pass fails.
//
// Part 1 : 8 directed tests, each showing one property of the designs.
// Part 2 : random campaign, K = 0 .. 2*N_MEM+2 faulty rows, TRIALS fault
//          sets per K, rows placed in random SRAMs. Reports the repair
//          success rate and repair coverage of both designs.
//
// Parameters : N_MEM (2), ROWS (256), WIDTH (8), TRIALS (20)
// Plusargs   : +TRIALS=<n>  +SEED=<s>  +VERBOSE (print every random run)
//
// Run (ModelSim):
//   vlog +define+FAULT_INJECT +incdir+<rtl/include> rtl/*.v tb/tb_bisr_compare.v
//   vsim -c -G/tb_bisr_compare/N_MEM=4 work.tb_bisr_compare +TRIALS=50 -do "run -all; quit"
//   (use the full path: a plain -GN_MEM also overrides the N_MEM = 1 inside
//    every dedicated BISR and breaks it)
//============================================================================
`timescale 1ns/1ps
`include "bisr_defines.vh"

module tb_bisr_compare;

    // ==================================================================
    // Parameters
    // ==================================================================
    parameter N_MEM  = 2;       // number of SRAMs
    parameter ROWS   = 256;     // rows per SRAM
    parameter WIDTH  = 8;       // bits per row
    parameter TRIALS = 20;      // random fault sets per K (Part 2)

    // Shared design: up to 4 SRAMs per controller
    localparam CL      = (N_MEM <= 4) ? N_MEM : 4;   // SRAMs per controller
    localparam N_CTRL  = N_MEM / CL;                  // shared controllers
    localparam NG_CL   = CL;                          // global spares per controller
    localparam FT_SH   = CL + NG_CL;                  // fault-table entries per controller

    // Dedicated design: 2 local spares per SRAM, table sized to match
    localparam NL_DED  = 2;
    localparam FT_DED  = 2;

    localparam SPARES  = 2 * N_MEM;                   // same in both designs
    localparam ADDR_W  = (ROWS > 1) ? $clog2(ROWS) : 1;
    localparam LW_SH   = 1;                           // $clog2(1+1)
    localparam LW_DED  = 2;                           // $clog2(2+1)
    localparam KMAX    = SPARES + 2;                  // random K range 0..KMAX
    localparam MAXF    = 64;                          // fault-list capacity
    localparam TIMEOUT = 40 * ROWS * N_MEM + 2000;    // cycles per BISR run

    // ==================================================================
    // Clock, reset, shared stimulus
    // ==================================================================
    reg clk = 1'b0;
    always #5 clk = ~clk;                             // 100 MHz

    reg rst_n = 1'b0, bisr_start = 1'b0;

    // Functional ports: the same stimulus drives both designs
    reg  [N_MEM*ADDR_W-1:0] f_addr  = 0;
    reg  [N_MEM-1:0]        f_we    = 0, f_re = 0;
    reg  [N_MEM*WIDTH-1:0]  f_wdata = 0;

    // ==================================================================
    // DUT 1 : SHARED BISR
    // ==================================================================
    wire                    sh_busy, sh_done, sh_pass, sh_unrep, sh_ovf, sh_vfail;
    wire [15:0]             sh_fcnt;
    wire [N_MEM*LW_SH-1:0]  sh_lused;
    wire [7:0]              sh_gused;
    wire [N_MEM*WIDTH-1:0]  sh_rdata;

    clustered_bisr_top #(
        .N_MEM        (N_MEM),
        .CLUSTER      (CL),
        .ROWS         (ROWS),
        .WIDTH        (WIDTH),
        .N_LOCAL      (1),
        .N_GLOBAL     (NG_CL),
        .FT_DEPTH     (FT_SH),
        .SPARE_GATING (1)
    ) u_sh (
        .clk (clk), .rst_n (rst_n), .scan_en (1'b0), .bisr_start (bisr_start),
        .bisr_busy (sh_busy), .bisr_done (sh_done), .bisr_pass (sh_pass),
        .bisr_unrepairable (sh_unrep), .bisr_overflow (sh_ovf),
        .bisr_verify_fail (sh_vfail), .bisr_fault_count (sh_fcnt),
        .bisr_local_used (sh_lused), .bisr_global_used (sh_gused),
        .func_addr (f_addr), .func_we (f_we), .func_re (f_re),
        .func_wdata (f_wdata), .func_rdata (sh_rdata)
    );

    // ==================================================================
    // DUT 2 : DEDICATED BISR
    // ==================================================================
    wire                    dd_busy, dd_done, dd_pass, dd_unrep, dd_ovf, dd_vfail;
    wire [15:0]             dd_fcnt;
    wire [N_MEM*LW_DED-1:0] dd_lused;
    wire [7:0]              dd_gused;
    wire [N_MEM*WIDTH-1:0]  dd_rdata;

    dedicated_bisr_top #(
        .N_MEM        (N_MEM),
        .ROWS         (ROWS),
        .WIDTH        (WIDTH),
        .N_LOCAL      (NL_DED),
        .FT_DEPTH     (FT_DED),
        .SPARE_GATING (1)
    ) u_dd (
        .clk (clk), .rst_n (rst_n), .scan_en (1'b0), .bisr_start (bisr_start),
        .bisr_busy (dd_busy), .bisr_done (dd_done), .bisr_pass (dd_pass),
        .bisr_unrepairable (dd_unrep), .bisr_overflow (dd_ovf),
        .bisr_verify_fail (dd_vfail), .bisr_fault_count (dd_fcnt),
        .bisr_local_used (dd_lused), .bisr_global_used (dd_gused),
        .func_addr (f_addr), .func_we (f_we), .func_re (f_re),
        .func_wdata (f_wdata), .func_rdata (dd_rdata)
    );

    // ==================================================================
    // Fault injection
    // `add_fault` sets inj_* and fires inj_ev; the blocks below put the
    // same fault into the matching fault_injector of BOTH designs.
    //   SRAM g of the shared design = SRAM (g % CL) of controller (g / CL)
    // ==================================================================
    integer inj_tgt, inj_mem, inj_row, inj_bit, inj_type;
    event   inj_ev, clr_ev;

    genvar g;
    generate
        for (g = 0; g < N_MEM; g = g + 1) begin : g_fi
            always @(inj_ev) begin
                if (inj_mem == g && inj_tgt == `TGT_MAIN) begin
                    u_dd.g_inst[g].u_bisr.g_mem[0].u_wrap.u_fi.add_fault(inj_row, inj_bit, inj_type);
                    u_sh.g_cl[g/CL].u_bisr.g_mem[g%CL].u_wrap.u_fi.add_fault(inj_row, inj_bit, inj_type);
                end
                // local spare row 0 of SRAM g (the first spare each design uses)
                if (inj_mem == g && inj_tgt == `TGT_LOCAL) begin
                    u_dd.g_inst[g].u_bisr.g_mem[0].u_wrap.u_local.g_row[0].u_fi.add_fault(0, inj_bit, inj_type);
                    u_sh.g_cl[g/CL].u_bisr.g_mem[g%CL].u_wrap.u_local.g_row[0].u_fi.add_fault(0, inj_bit, inj_type);
                end
            end
            always @(clr_ev) begin
                u_dd.g_inst[g].u_bisr.g_mem[0].u_wrap.u_fi.clear_faults;
                u_dd.g_inst[g].u_bisr.g_mem[0].u_wrap.u_local.g_row[0].u_fi.clear_faults;
                u_sh.g_cl[g/CL].u_bisr.g_mem[g%CL].u_wrap.u_fi.clear_faults;
                u_sh.g_cl[g/CL].u_bisr.g_mem[g%CL].u_wrap.u_local.g_row[0].u_fi.clear_faults;
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // Fault list of the current test (for printing and the model)
    // ------------------------------------------------------------------
    integer nf;
    integer fl_tgt  [0:MAXF-1];
    integer fl_mem  [0:MAXF-1];
    integer fl_row  [0:MAXF-1];
    integer fl_bit  [0:MAXF-1];
    integer fl_type [0:MAXF-1];
    reg     spare_bad [0:N_MEM-1];     // local spare 0 of SRAM m is faulty
    integer i_tmp;

    task clear_faults;
        begin
            -> clr_ev; #1;
            nf = 0;
            for (i_tmp = 0; i_tmp < N_MEM; i_tmp = i_tmp + 1) spare_bad[i_tmp] = 1'b0;
        end
    endtask

    task add_fault(input integer tgt, input integer mem, input integer row,
                   input integer bitp, input integer ftype);
        begin
            inj_tgt = tgt; inj_mem = mem; inj_row = row; inj_bit = bitp; inj_type = ftype;
            -> inj_ev; #1;
            if (tgt == `TGT_LOCAL) spare_bad[mem] = 1'b1;
            if (nf < MAXF) begin
                fl_tgt[nf] = tgt; fl_mem[nf] = mem; fl_row[nf] = row;
                fl_bit[nf] = bitp; fl_type[nf] = ftype;
                nf = nf + 1;
            end
        end
    endtask

    // ==================================================================
    // Reference model
    // ==================================================================
    integer k_m [0:N_MEM-1];            // distinct faulty rows per SRAM
    integer k_total;

    // expected results
    reg     e_dd_pass, e_dd_unrep, e_dd_vfail;
    reg     e_sh_pass, e_sh_unrep, e_sh_vfail, e_sh_cmp;
    integer e_dd_used, e_sh_used, e_sh_l, e_sh_g;
    reg [8*80:1] e_dd_why, e_sh_why;

    function integer imin(input integer a, input integer b);
        imin = (a < b) ? a : b;
    endfunction

    task compute_expected;
        integer i, j, m, c, dup, dist, extra, first;
        begin
            // ---- distinct faulty rows per SRAM ----
            for (m = 0; m < N_MEM; m = m + 1) k_m[m] = 0;
            k_total = 0;
            for (i = 0; i < nf; i = i + 1) begin
                if (fl_tgt[i] == `TGT_MAIN) begin
                    dup = 0;
                    for (j = 0; j < i; j = j + 1)
                        if (fl_tgt[j] == `TGT_MAIN && fl_mem[j] == fl_mem[i] && fl_row[j] == fl_row[i])
                            dup = 1;
                    if (!dup) begin
                        k_m[fl_mem[i]] = k_m[fl_mem[i]] + 1;
                        k_total = k_total + 1;
                    end
                end
            end

            // ---- DEDICATED: every SRAM on its own, 2 local spares ----
            e_dd_unrep = 0; e_dd_vfail = 0; e_dd_used = 0;
            e_dd_why = "all faulty rows replaced";
            first = 1;
            for (m = 0; m < N_MEM; m = m + 1) begin
                e_dd_used = e_dd_used + imin(k_m[m], NL_DED);
                if (k_m[m] > NL_DED) begin
                    if (first) $sformat(e_dd_why, "SRAM%0d has %0d faulty rows but only %0d spare rows",
                                        m, k_m[m], NL_DED);
                    first = 0;
                    e_dd_unrep = 1;
                end
            end
            for (m = 0; m < N_MEM; m = m + 1)
                if (k_m[m] <= NL_DED && k_m[m] >= 1 && spare_bad[m]) begin
                    if (!e_dd_unrep)
                        $sformat(e_dd_why, "spare row given to SRAM%0d is itself faulty (caught by VERIFY)", m);
                    e_dd_vfail = 1;
                end
            e_dd_pass = !e_dd_unrep && !e_dd_vfail;

            // ---- SHARED: per controller, local first, then the pool ----
            e_sh_unrep = 0; e_sh_vfail = 0; e_sh_used = 0; e_sh_l = 0; e_sh_g = 0;
            e_sh_cmp = 1;
            e_sh_why = "all faulty rows replaced";
            first = 1;
            for (c = 0; c < N_CTRL; c = c + 1) begin
                dist = 0; extra = 0;
                for (m = c*CL; m < (c+1)*CL; m = m + 1) begin
                    dist   = dist + k_m[m];
                    e_sh_l = e_sh_l + imin(k_m[m], 1);
                    extra  = extra + k_m[m] - imin(k_m[m], 1);
                end
                e_sh_g = e_sh_g + imin(extra, NG_CL);
                if (dist > FT_SH) begin
                    // fault table full: which rows got logged depends on test
                    // order, so spare counts are not compared
                    e_sh_cmp = 0;
                    e_sh_unrep = 1;
                    if (first) $sformat(e_sh_why,
                        "controller %0d: %0d faulty rows, fault table holds %0d", c, dist, FT_SH);
                    first = 0;
                end else if (extra > NG_CL) begin
                    e_sh_unrep = 1;
                    if (first) $sformat(e_sh_why,
                        "controller %0d: %0d rows need a global spare, pool has %0d", c, extra, NG_CL);
                    first = 0;
                end else begin
                    for (m = c*CL; m < (c+1)*CL; m = m + 1)
                        if (k_m[m] >= 1 && spare_bad[m]) begin
                            e_sh_vfail = 1;
                            if (first) $sformat(e_sh_why,
                                "spare row given to SRAM%0d is itself faulty (caught by VERIFY)", m);
                        end
                end
            end
            e_sh_used = e_sh_l + e_sh_g;
            e_sh_pass = !e_sh_unrep && !e_sh_vfail;
        end
    endtask

    // ==================================================================
    // Run the BISR of both designs in parallel
    // ==================================================================
    integer cyc_sh, cyc_dd;
    reg     timed_out;

    task run_bisr;
        integer cyc;
        begin
            @(negedge clk) bisr_start = 1'b1;
            @(negedge clk) bisr_start = 1'b0;
            cyc = 0; cyc_sh = 0; cyc_dd = 0;
            while (!(sh_done && dd_done) && cyc < TIMEOUT) begin
                @(negedge clk);
                cyc = cyc + 1;
                if (sh_done && cyc_sh == 0) cyc_sh = cyc;
                if (dd_done && cyc_dd == 0) cyc_dd = cyc;
            end
            timed_out = !(sh_done && dd_done);
        end
    endtask

    // ==================================================================
    // Read/write check after repair: every row of every SRAM must store
    // and return its own pattern through the functional ports.
    // ==================================================================
    function [WIDTH-1:0] pattern(input integer m, input integer r);
        pattern = r * 7 + m * 31 + 8'h5A;
    endfunction

    integer rw_err_sh, rw_err_dd;

    task rw_check;
        integer r, m;
        begin
            rw_err_sh = 0; rw_err_dd = 0;
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
                for (m = 0; m < N_MEM; m = m + 1) begin
                    if (sh_rdata[m*WIDTH +: WIDTH] !== pattern(m, r)) rw_err_sh = rw_err_sh + 1;
                    if (dd_rdata[m*WIDTH +: WIDTH] !== pattern(m, r)) rw_err_dd = rw_err_dd + 1;
                end
            end
        end
    endtask

    // ==================================================================
    // Pretty-printing helpers
    // ==================================================================
    function [8*12:1] status_str(input p, input u, input v);
        status_str = p ? "PASS        " :
                     v ? "VERIFY FAIL " :
                     u ? "UNREPAIRABLE" : "NOT DONE    ";
    endfunction

    function [8*15:1] type_str(input integer t);
        case (t)
            `FT_SA0:     type_str = "stuck-at-0     ";
            `FT_SA1:     type_str = "stuck-at-1     ";
            `FT_TF_UP:   type_str = "0->1 transition";
            default:     type_str = "1->0 transition";
        endcase
    endfunction

    task print_faults;
        integer i;
        begin
            if (nf == 0)
                $display("    Faults : none");
            for (i = 0; i < nf; i = i + 1) begin
                if (fl_tgt[i] == `TGT_MAIN)
                    $display("    %s SRAM%0d  row %3d  bit %0d  %0s",
                             (i == 0) ? "Faults :" : "        ", fl_mem[i], fl_row[i], fl_bit[i], type_str(fl_type[i]));
                else
                    $display("    %s SRAM%0d  LOCAL SPARE ROW  bit %0d  %0s",
                             (i == 0) ? "Faults :" : "        ", fl_mem[i], fl_bit[i], type_str(fl_type[i]));
            end
        end
    endtask

    // ==================================================================
    // Check one run of both designs against the model
    // ==================================================================
    integer n_checks = 0, n_fail = 0;
    reg     ok_dd, ok_sh;               // result matches the model
    integer used_dd, used_sh, l_sh;     // spares used as reported by the DUT

    task check_run(input verbose);
        integer m;
        reg     st_dd, st_sh, sp_dd, sp_sh, rw_dd, rw_sh;
        begin
            compute_expected;
            run_bisr;

            // spares used, as reported by each design
            used_dd = 0; l_sh = 0;
            for (m = 0; m < N_MEM; m = m + 1) begin
                used_dd = used_dd + dd_lused[m*LW_DED +: LW_DED];
                l_sh    = l_sh    + sh_lused[m*LW_SH  +: LW_SH];
            end
            used_sh = l_sh + sh_gused;

            // 1) repair outcome
            st_dd = !timed_out && (dd_pass === e_dd_pass) && (dd_unrep === e_dd_unrep) && (dd_vfail === e_dd_vfail);
            st_sh = !timed_out && (sh_pass === e_sh_pass) && (sh_unrep === e_sh_unrep) && (sh_vfail === e_sh_vfail);
            // 2) spares used
            sp_dd = (used_dd == e_dd_used);
            sp_sh = !e_sh_cmp || (used_sh == e_sh_used);
            // 3) read/write through the repaired memories
            rw_err_sh = 0; rw_err_dd = 0;
            if (dd_pass === 1'b1 || sh_pass === 1'b1) rw_check;
            rw_dd = (dd_pass !== 1'b1) || (rw_err_dd == 0);
            rw_sh = (sh_pass !== 1'b1) || (rw_err_sh == 0);

            ok_dd = st_dd && sp_dd && rw_dd;
            ok_sh = st_sh && sp_sh && rw_sh;

            n_checks = n_checks + 2 + 2 + (dd_pass === 1'b1) + (sh_pass === 1'b1);
            n_fail   = n_fail + !st_dd + !st_sh + !sp_dd + !sp_sh + !rw_dd + !rw_sh;

            if (verbose || !ok_dd || !ok_sh) begin
                $display("      Dedicated : %s  spares used %2d/%2d            expected %s  %s",
                         status_str(dd_pass, dd_unrep, dd_vfail), used_dd, SPARES,
                         status_str(e_dd_pass, e_dd_unrep, e_dd_vfail), ok_dd ? "[OK]" : "[MISMATCH]");
                if (!e_dd_pass)
                    $display("                  why: %0s", e_dd_why);
                $display("      Shared    : %s  spares used %2d/%2d (L%0d + G%0d)  expected %s  %s",
                         status_str(sh_pass, sh_unrep, sh_vfail), used_sh, SPARES, l_sh, sh_gused,
                         status_str(e_sh_pass, e_sh_unrep, e_sh_vfail), ok_sh ? "[OK]" : "[MISMATCH]");
                if (!e_sh_pass)
                    $display("                  why: %0s", e_sh_why);
                if (dd_pass === 1'b1 || sh_pass === 1'b1)
                    $display("      Read/write of all %0d rows after repair : dedicated %0s | shared %0s",
                             ROWS,
                             (dd_pass !== 1'b1) ? "-" : (rw_err_dd == 0) ? "OK" : "ERRORS",
                             (sh_pass !== 1'b1) ? "-" : (rw_err_sh == 0) ? "OK" : "ERRORS");
                if (timed_out)
                    $display("      ** TIMEOUT: BISR did not finish in %0d cycles", TIMEOUT);
                if (!sp_dd) $display("      ** dedicated spares used %0d, expected %0d", used_dd, e_dd_used);
                if (!sp_sh) $display("      ** shared spares used %0d, expected %0d", used_sh, e_sh_used);
            end
        end
    endtask

    // ==================================================================
    // Part 1 : directed tests
    // ==================================================================
    integer test_no = 0;
    integer bisr_cyc_sh, bisr_cyc_dd;

    task test_header(input [8*60:1] title, input [8*80:1] shows);
        begin
            test_no = test_no + 1;
            $display("");
            $display("T%0d  %0s", test_no, title);
            $display("    Shows  : %0s", shows);
        end
    endtask

    task directed_tests;
        integer m, r, last;
        begin
            $display("");
            $display("PART 1 - DIRECTED TESTS");
            $display("--------------------------------------------------------------------------------");

            // T1
            test_header("No faults", "a fault-free system passes and uses no spares");
            clear_faults; print_faults; check_run(1);
            bisr_cyc_sh = cyc_sh; bisr_cyc_dd = cyc_dd;

            // T2
            test_header("One faulty row in every SRAM",
                        "each SRAM repairs with its own local spare");
            clear_faults;
            for (m = 0; m < N_MEM; m = m + 1)
                add_fault(`TGT_MAIN, m, (10 + 37*m) % ROWS, m % WIDTH, m % 4);
            print_faults; check_run(1);

            // T3
            test_header("Several bad bits in one row",
                        "bad bits in the same row are merged and use ONE spare row");
            clear_faults;
            add_fault(`TGT_MAIN, 0, 50 % ROWS, 0, `FT_SA0);
            add_fault(`TGT_MAIN, 0, 50 % ROWS, 1, `FT_SA1);
            add_fault(`TGT_MAIN, 0, 50 % ROWS, 6, `FT_TF_UP);
            print_faults; check_run(1);

            // T4
            test_header("Three faulty rows in SRAM0",
                        "dedicated runs out (2 spares); shared borrows 2 global spares");
            clear_faults;
            add_fault(`TGT_MAIN, 0,   5 % ROWS, 0, `FT_SA0);
            add_fault(`TGT_MAIN, 0, 100 % ROWS, 4, `FT_TF_UP);
            add_fault(`TGT_MAIN, 0, 250 % ROWS, 6, `FT_TF_DOWN);
            print_faults; check_run(1);

            // T5
            test_header("Two faulty rows in SRAM0 and two in SRAM1",
                        "both repair: dedicated uses 2+2 local, shared 2 local + 2 global");
            clear_faults;
            add_fault(`TGT_MAIN, 0, 7, 2, `FT_SA0);
            add_fault(`TGT_MAIN, 0, 9, 5, `FT_SA1);
            add_fault(`TGT_MAIN, 1, 7, 3, `FT_TF_DOWN);
            add_fault(`TGT_MAIN, 1, 9, 4, `FT_TF_UP);
            print_faults; check_run(1);

            // T6
            last = N_MEM - 1;
            test_header("Three faulty rows in the LAST SRAM",
                        "the global pool can be borrowed by any SRAM of its controller");
            clear_faults;
            for (r = 0; r < 3; r = r + 1)
                add_fault(`TGT_MAIN, last, (3 + 11*r) % ROWS, r % WIDTH, `FT_SA1);
            print_faults; check_run(1);

            // T7
            test_header("More faulty rows in SRAM0 than any design can cover",
                        "limit: 1 local + whole pool for shared, 2 local for dedicated");
            clear_faults;
            for (r = 0; r < NG_CL + 2; r = r + 1)
                add_fault(`TGT_MAIN, 0, (20 + 13*r) % ROWS, r % WIDTH, r % 4);
            print_faults; check_run(1);

            // T8
            test_header("Faulty spare row",
                        "a defective spare is caught by the VERIFY pass in both designs");
            clear_faults;
            add_fault(`TGT_MAIN,  0, 20 % ROWS, 0, `FT_SA1);
            add_fault(`TGT_LOCAL, 0, 0,         2, `FT_SA0);
            print_faults; check_run(1);
        end
    endtask

    // ==================================================================
    // Part 2 : random campaign
    // ==================================================================
    integer runs_k [0:KMAX];
    integer dd_ok_k[0:KMAX], sh_ok_k[0:KMAX], mism_k[0:KMAX];
    integer rows_k [0:KMAX], dd_rep_k[0:KMAX], sh_rep_k[0:KMAX];

    task random_campaign(input integer trials, input integer seed_in, input verbose);
        integer seed, k, t, f, m, r, i, dup, run_no;
        begin
            seed = seed_in; run_no = 0;
            $display("");
            $display("PART 2 - RANDOM FAULT CAMPAIGN");
            $display("--------------------------------------------------------------------------------");
            $display("  K = number of faulty rows (K = 0..%0d). %0d random fault sets per K, seed %0d.",
                     KMAX, trials, seed_in);
            $display("  Every faulty row is placed in a random SRAM at a random row/bit with a");
            $display("  random fault type. Both designs get exactly the same fault sets.");
            $display("  (one row is printed as soon as each K is finished)");
            $display("");
            $display("   K  | sets |   DEDICATED repaired    |    SHARED repaired      | mismatches");
            $display("  ----+------+-------------------------+-------------------------+-----------");
            for (k = 0; k <= KMAX; k = k + 1) begin
                runs_k[k] = 0; dd_ok_k[k] = 0; sh_ok_k[k] = 0; mism_k[k] = 0;
                rows_k[k] = 0; dd_rep_k[k] = 0; sh_rep_k[k] = 0;
            end

            for (k = 0; k <= KMAX; k = k + 1) begin
                for (t = 0; t < trials; t = t + 1) begin
                    clear_faults;
                    f = 0;
                    while (f < k) begin
                        m = {$random(seed)} % N_MEM;
                        r = {$random(seed)} % ROWS;
                        dup = 0;
                        for (i = 0; i < nf; i = i + 1)
                            if (fl_mem[i] == m && fl_row[i] == r) dup = 1;
                        if (!dup) begin
                            add_fault(`TGT_MAIN, m, r, {$random(seed)} % WIDTH, {$random(seed)} % 4);
                            f = f + 1;
                        end
                    end
                    run_no = run_no + 1;
                    if (verbose) $display("  run %0d  (K = %0d)", run_no, k);
                    check_run(verbose);
                    if (!ok_dd || !ok_sh) begin
                        $write("  ^ mismatch in run %0d (K=%0d), rows per SRAM [", run_no, k);
                        for (i = 0; i < N_MEM; i = i + 1)
                            $write("%0d%0s", k_m[i], (i < N_MEM-1) ? "," : "");
                        $write("]\n");
                    end
                    runs_k[k]   = runs_k[k] + 1;
                    dd_ok_k[k]  = dd_ok_k[k] + (dd_pass === 1'b1);
                    sh_ok_k[k]  = sh_ok_k[k] + (sh_pass === 1'b1);
                    mism_k[k]   = mism_k[k] + (!ok_dd || !ok_sh);
                    rows_k[k]   = rows_k[k] + k;
                    dd_rep_k[k] = dd_rep_k[k] + used_dd;
                    sh_rep_k[k] = sh_rep_k[k] + used_sh;
                end
                $display("  %3d | %4d | %4d of %4d (%5.1f %%) | %4d of %4d (%5.1f %%) |    %0d",
                         k, runs_k[k],
                         dd_ok_k[k], runs_k[k], 100.0 * dd_ok_k[k] / runs_k[k],
                         sh_ok_k[k], runs_k[k], 100.0 * sh_ok_k[k] / runs_k[k],
                         mism_k[k]);
            end

        end
    endtask

    // ==================================================================
    // Summary
    // ==================================================================
    task summary(input did_random);
        integer k, sets, dd_ok, sh_ok, rows, dd_rep, sh_rep;
        begin
            $display("");
            $display("================================================================================");
            $display("SUMMARY");
            $display("--------------------------------------------------------------------------------");
            $display("  Spare rows          : %0d in both designs", SPARES);
            $display("  BISR time (no faults): dedicated %0d cycles, shared %0d cycles",
                     bisr_cyc_dd, bisr_cyc_sh);
            $display("                         (shared tests its %0d SRAMs one after another)", CL);
            if (did_random) begin
                sets = 0; dd_ok = 0; sh_ok = 0; rows = 0; dd_rep = 0; sh_rep = 0;
                for (k = 1; k <= KMAX; k = k + 1) begin
                    sets   = sets   + runs_k[k];
                    dd_ok  = dd_ok  + dd_ok_k[k];
                    sh_ok  = sh_ok  + sh_ok_k[k];
                    rows   = rows   + rows_k[k];
                    dd_rep = dd_rep + dd_rep_k[k];
                    sh_rep = sh_rep + sh_rep_k[k];
                end
                $display("");
                $display("  Repair success rate  (fault sets with K >= 1 where the whole system passed)");
                $display("      Dedicated : %5d / %5d = %5.1f %%", dd_ok, sets, 100.0 * dd_ok / sets);
                $display("      Shared    : %5d / %5d = %5.1f %%", sh_ok, sets, 100.0 * sh_ok / sets);
                $display("");
                $display("  Repair coverage      (faulty rows that were given a spare row)");
                $display("      Dedicated : %5d / %5d = %5.1f %%", dd_rep, rows, 100.0 * dd_rep / rows);
                $display("      Shared    : %5d / %5d = %5.1f %%", sh_rep, rows, 100.0 * sh_rep / rows);
            end
            $display("");
            $display("  Checks              : %0d run, %0d failed", n_checks, n_fail);
            $display("--------------------------------------------------------------------------------");
            if (n_fail == 0)
                $display("  RESULT : ALL CHECKS PASSED");
            else
                $display("  RESULT : %0d CHECK(S) FAILED - see [MISMATCH] lines above", n_fail);
            $display("================================================================================");
        end
    endtask

    // ==================================================================
    // Main
    // ==================================================================
    integer trials, seed;
    reg     verbose;

    initial begin
        if (!$value$plusargs("TRIALS=%d", trials)) trials = TRIALS;
        if (!$value$plusargs("SEED=%d",   seed))   seed   = 1;
        verbose = $test$plusargs("VERBOSE");

        $display("================================================================================");
        $display("  SHARED vs DEDICATED BISR  -  REPAIR VERIFICATION");
        $display("================================================================================");
        $display("  Memories  : %0d SRAMs, %0d rows x %0d bits each", N_MEM, ROWS, WIDTH);
        $display("  Dedicated : %0d BISR controllers (one per SRAM)", N_MEM);
        $display("              2 local spare rows per SRAM                    -> %0d spare rows", SPARES);
        $display("  Shared    : %0d BISR controller(s), %0d SRAMs per controller", N_CTRL, CL);
        $display("              1 local spare row per SRAM + %0d global spare rows", NG_CL);
        $display("              per controller (borrowable by any of its SRAMs) -> %0d spare rows", SPARES);
        $display("--------------------------------------------------------------------------------");
        $display("  Each test : inject faults -> run BISR on both designs -> compare with the");
        $display("              expected result -> if repaired, write/read every row");
        $display("  Results   : PASS         all faulty rows replaced and VERIFY clean");
        $display("              UNREPAIRABLE not enough spare rows (or fault table full)");
        $display("              VERIFY FAIL  an assigned spare row is itself faulty");
        $display("              [OK]         design result = expected result");
        $display("              L / G        local / global spare rows used (shared)");
        $display("================================================================================");

        if (N_MEM < 2 || (N_MEM % CL) != 0) begin
            $display("ERROR: N_MEM must be >= 2 and, above 4, a multiple of 4");
            $finish;
        end

        clear_faults;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        directed_tests;
        if (trials > 0) random_campaign(trials, seed, verbose);
        summary(trials > 0);
        $finish;
    end

endmodule
