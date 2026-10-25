# =============================================================================
# run.do  -  ModelSim / Questa, one-click flow (no project, no paths to set)
#
#   1. In ModelSim: File > Change Directory...  -> pick this BISR folder
#   2. In the Transcript:   do run.do
#      (compiles everything with the right include path and FAULT_INJECT)
#   3. Then type one of:
#        compare 2                 shared vs dedicated, 2 SRAMs, 20 sets per K
#        compare 4 10 64           4 SRAMs, 10 sets per K, 64-row SRAMs (fast)
#        compare 8 10 64           8 SRAMs
#        tests                     unit tests + system tests
#
#   compare <N_MEM> [TRIALS=20] [ROWS=256] [SEED=1]
#   Each compare run saves its full report as compare_N<n>.log in this folder.
#
# Testbench parameters are overridden with their full path (-G/tb/PARAM).
# A plain -GN_MEM would also change the N_MEM = 1 inside every dedicated BISR.
# =============================================================================

if {![file exists rtl/include/bisr_defines.vh]} {
    echo "ERROR: run this from the BISR folder (File > Change Directory...)"
} else {

    # ---------------- compile ----------------
    if {[file exists work]} { vdel -lib work -all }
    vlib work
    eval vlog -work work +define+FAULT_INJECT +incdir+rtl/include \
        [lsort [glob rtl/*.v]] [lsort [glob tb/*.v]]

    # ---------------- shared vs dedicated report ----------------
    proc compare {n {trials 20} {rows 256} {seed 1}} {
        transcript file compare_N$n.log
        vsim -onfinish stop -G/tb_bisr_compare/N_MEM=$n -G/tb_bisr_compare/ROWS=$rows \
             work.tb_bisr_compare +TRIALS=$trials +SEED=$seed
        run -all
        quit -sim
        transcript file transcript
        echo "Report saved to compare_N$n.log"
    }

    # ---------------- unit + system tests ----------------
    proc tests {} {
        foreach tb {tb_sram_injector tb_march tb_logger tb_bira tb_remap} {
            vsim -onfinish stop work.$tb
            run -all
            quit -sim
        }
        # shared (1 local / SRAM + 2 global)
        vsim -onfinish stop -G/tb_top_scenarios/ARCH=0 work.tb_top_scenarios
        run -all
        quit -sim
        # dedicated (2 local / SRAM)
        vsim -onfinish stop -G/tb_top_scenarios/ARCH=1 -G/tb_top_scenarios/N_LOCAL=2 \
             -G/tb_top_scenarios/FT_DEPTH=2 work.tb_top_scenarios
        run -all
        quit -sim
        # shared, 8 SRAMs in 2 groups of 4
        vsim -onfinish stop -G/tb_top_scenarios/ARCH=2 -G/tb_top_scenarios/N_MEM=8 \
             -G/tb_top_scenarios/CLUSTER=4 -G/tb_top_scenarios/N_GLOBAL=4 \
             -G/tb_top_scenarios/FT_DEPTH=8 -G/tb_top_scenarios/ROWS=64 work.tb_top_scenarios
        run -all
        quit -sim
    }

    echo ""
    echo "Compiled. Now type:  compare 2    (or: compare 4 10 64, compare 8 10 64, tests)"
}
