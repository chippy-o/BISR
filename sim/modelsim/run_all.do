# =============================================================================
# ModelSim / Questa: compile everything and run all tests in batch mode.
#
#   cd sim/modelsim
#   vsim -c -do run_all.do
#
# Each testbench prints "ALL CHECKS PASSED" / "ALL n RUN(S) MATCH ..." on success.
# =============================================================================

if {[file exists work]} { vdel -lib work -all }
vlib work

# FAULT_INJECT enables the simulation-only fault injectors
vlog -work work +define+FAULT_INJECT +incdir+../../rtl/include \
     ../../rtl/*.v ../../tb/*.v

# ---------------- unit tests ----------------
foreach tb {tb_sram_injector tb_march tb_logger tb_bira tb_remap} {
    vsim -c -quiet work.$tb
    run -all
    quit -sim
}

# ---------------- system tests ----------------
# proposed shared BISR (1 local / SRAM + 2 global)
vsim -c -quiet -GARCH=0 work.tb_top_scenarios
run -all
quit -sim

# dedicated baseline (1 local / SRAM)
vsim -c -quiet -GARCH=1 work.tb_top_scenarios
run -all
quit -sim

# equal-total-spares baseline (2 local / SRAM)
vsim -c -quiet -GARCH=1 -GN_LOCAL=2 work.tb_top_scenarios
run -all
quit -sim

# clustered: 8 SRAMs in 2 clusters of 4, 4 global spares per cluster
vsim -c -quiet -GARCH=2 -GN_MEM=8 -GCLUSTER=4 -GN_GLOBAL=4 -GFT_DEPTH=8 -GROWS=64 work.tb_top_scenarios
run -all
quit -sim

# random campaign on the shared design
vsim -c -quiet -GARCH=0 work.tb_top_scenarios +RANDOM=200 +SEED=1
run -all
quit -sim

quit -f
