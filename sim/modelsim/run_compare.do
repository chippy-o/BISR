# =============================================================================
# NOTE: parameters are overridden with their full path (-G/tb/PARAM). A plain
#       -GPARAM overrides that name in EVERY module, including the N_MEM = 1
#       inside each dedicated BISR, which breaks the design.
# ModelSim / Questa: SHARED vs DEDICATED repair verification (tb_bisr_compare)
#
#   cd sim/modelsim
#   vsim -c -do run_compare.do
#
# Runs 2, 4 and 8 SRAMs (256 x 8 each). Every run prints the directed tests,
# the random-campaign table and a SUMMARY ending in
#   RESULT : ALL CHECKS PASSED
# The full report of each run is also written to compare_N<n>.log.
#
# Change TRIALS for more random fault sets per K (more = slower, smoother %).
# =============================================================================

set TRIALS 20

if {[file exists work]} { vdel -lib work -all }
vlib work
vlog -work work +define+FAULT_INJECT +incdir+../../rtl/include \
     ../../rtl/*.v ../../tb/tb_bisr_compare.v

foreach N {2 4 8} {
    transcript file compare_N$N.log
    vsim -c -quiet -G/tb_bisr_compare/N_MEM=$N work.tb_bisr_compare +TRIALS=$TRIALS
    run -all
    quit -sim
}
transcript file transcript

quit -f
