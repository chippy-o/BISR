# =============================================================================
# ModelSim / Questa GUI: shared BISR directed scenarios with key waveforms.
#
#   cd sim/modelsim
#   vsim -do run_gui.do
#
# Change ARCH / N_LOCAL / ROWS below to look at the other configurations.
# ROWS=32 keeps the waveform short.
# =============================================================================

if {[file exists work]} { vdel -lib work -all }
vlib work
vlog -work work +define+FAULT_INJECT +incdir+../../rtl/include \
     ../../rtl/*.v ../../tb/tb_top_scenarios.v

vsim -voptargs=+acc -GARCH=0 -GROWS=32 work.tb_top_scenarios

add wave -divider "BISR control"
add wave sim:/tb_top_scenarios/clk
add wave sim:/tb_top_scenarios/bisr_start
add wave -radix unsigned sim:/tb_top_scenarios/g_dut/dut/u_ctrl/state
add wave sim:/tb_top_scenarios/done
add wave sim:/tb_top_scenarios/pass
add wave sim:/tb_top_scenarios/unrep
add wave sim:/tb_top_scenarios/vfail

add wave -divider "MBIST"
add wave -radix unsigned sim:/tb_top_scenarios/g_dut/dut/u_mbist/mem_sel
add wave -radix unsigned sim:/tb_top_scenarios/g_dut/dut/u_mbist/elem
add wave -radix unsigned sim:/tb_top_scenarios/g_dut/dut/u_mbist/addr
add wave sim:/tb_top_scenarios/g_dut/dut/u_mbist/fail_valid
add wave -radix unsigned sim:/tb_top_scenarios/g_dut/dut/u_mbist/fail_row

add wave -divider "Fault table / BIRA"
add wave -radix unsigned sim:/tb_top_scenarios/g_dut/dut/u_logger/count
add wave sim:/tb_top_scenarios/g_dut/dut/u_logger/overflow
add wave sim:/tb_top_scenarios/g_dut/dut/u_bira/rt_we
add wave -radix unsigned sim:/tb_top_scenarios/g_dut/dut/u_bira/global_used

add wave -divider "Remap / spares"
add wave sim:/tb_top_scenarios/g_dut/dut/r_hit
add wave sim:/tb_top_scenarios/g_dut/dut/r_is_global
add wave sim:/tb_top_scenarios/g_dut/dut/r_local_en
add wave sim:/tb_top_scenarios/g_dut/dut/r_global_en

run -all
wave zoom full
