#=============================================================================
# genus_common.tcl  -  shared Genus flow for the Shared BISR project
#
# Same flow as synth/genus_common.tcl (90nm slow.lib, 4 ns clock, medium
# effort, hierarchy kept), updated for the new RTL:
#   * reads clustered_bisr_top.v
#   * BLACKBOX_SRAM = 1 leaves sram_array out, so the main arrays are black
#     boxes and the reported area is BISR logic + spare rows only
#   * timing_report_unconstrained false, so _timing.rpt shows the real
#     critical path
#
# Do not run this file directly. Each syn_*.tcl sets
#   DESIGN         run name (used for every output file)
#   TOP            shared_bisr_top | dedicated_bisr_top | clustered_bisr_top
#   PARAMS         top-level parameter overrides, {{name value} ...}
#   BLACKBOX_SRAM  0 = synthesise sram_array as flip-flops, 1 = black box
# and then sources this file. Run from the syn/ directory (RTL in ../rtl).
#=============================================================================

#----------------------------------------------------------------------------
# Settings common to every run (keep identical for a fair comparison)
#----------------------------------------------------------------------------
set CLK_PERIOD 4.0          ;# ns (250 MHz), same as the lab template
set RTL_DIR    ../rtl
set OUT_DIR    outputs
set RPT_DIR    reports
if {![info exists BLACKBOX_SRAM]} { set BLACKBOX_SRAM 0 }

# Synthesisable RTL only: no fault_injector.v, no testbenches.
set RTL_FILES {
    spare_icg.v
    spare_row_bank.v
    sram_wrapper.v
    march_cminus.v
    fault_logger.v
    bira.v
    repair_table.v
    remap_unit.v
    bisr_ctrl_fsm.v
    shared_bisr_top.v
    dedicated_bisr_top.v
    clustered_bisr_top.v
}
if {!$BLACKBOX_SRAM} { set RTL_FILES [linsert $RTL_FILES 0 sram_array.v] }

file mkdir $OUT_DIR $RPT_DIR

#----------------------------------------------------------------------------
# Library
#----------------------------------------------------------------------------
set_db init_lib_search_path /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/
read_libs slow.lib

#----------------------------------------------------------------------------
# RTL
#----------------------------------------------------------------------------
# Keep every module as its own hierarchy so report_area gives a per-block
# breakdown (MBIST, fault logger, BIRA, repair table, remap, ...).
set_db auto_ungroup none

# sram_array not read -> unresolved module -> kept as a black box
if {$BLACKBOX_SRAM} { set_db hdl_error_on_blackbox false }

set_db init_hdl_search_path $RTL_DIR
read_hdl -sv $RTL_FILES

if {[llength $PARAMS] > 0} {
    elaborate $TOP -parameters $PARAMS
} else {
    elaborate $TOP
}

check_design -unresolved > $RPT_DIR/${DESIGN}_check.rpt

#----------------------------------------------------------------------------
# Constraints
#----------------------------------------------------------------------------
create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_transition -rise 0.1 [get_clocks clk]
set_clock_transition -fall 0.1 [get_clocks clk]
set_clock_uncertainty 0.01 [get_clocks clk]

set_input_delay  0.01 -clock clk [get_ports {rst_n scan_en bisr_start func_addr[*] func_we[*] func_re[*] func_wdata[*]}]
set_output_delay 0.01 -clock clk [all_outputs]

# Functional mode: scan_en = 0, so the spare-row clock gates are timed as
# real gates (scan_en only forces them on during scan shift).
set_case_analysis 0 [get_ports scan_en]

#----------------------------------------------------------------------------
# Synthesis
#----------------------------------------------------------------------------
set_db syn_generic_effort medium
set_db syn_map_effort     medium
set_db syn_opt_effort     medium

syn_generic
syn_map
syn_opt
write_hdl > $OUT_DIR/${DESIGN}_netlist.v
write_sdc > $OUT_DIR/${DESIGN}.sdc

#----------------------------------------------------------------------------
# Optional switching activity for power
#   export VCD=/path/to/dump.vcd   before running genus
# Without it, report_power is vectorless (default toggle rates): fine for
# area, not valid for the SPARE_GATING power comparison.
#----------------------------------------------------------------------------
if {[info exists ::env(VCD)] && [file exists $::env(VCD)]} {
    read_stimulus -file $::env(VCD) -dut_instance /tb_top_scenarios/g_dut/dut
}

#----------------------------------------------------------------------------
# Reports
#----------------------------------------------------------------------------
report_area  > $RPT_DIR/${DESIGN}_area.rpt     ;# hierarchical, per block
report_gates > $RPT_DIR/${DESIGN}_gates.rpt
report_power > $RPT_DIR/${DESIGN}_power.rpt

set_db timing_report_unconstrained false
report_timing > $RPT_DIR/${DESIGN}_timing.rpt

report_qor > $RPT_DIR/${DESIGN}_qor.rpt

#----------------------------------------------------------------------------
# Area split: total vs. SRAM storage arrays vs. everything else (BISR)
# With BLACKBOX_SRAM = 1 the arrays have no area, so BISR = total.
# One line is also appended to reports/area_summary.csv.
#----------------------------------------------------------------------------
if {[catch {
    set total 0.0
    foreach i [get_db insts] { set total [expr {$total + [get_db $i .area]}] }

    set arr 0.0
    set n_arr 0
    foreach h [get_db hinsts] {
        if {[string match sram_array* [get_db $h .module.name]]} {
            incr n_arr
            foreach i [get_db $h .insts] { set arr [expr {$arr + [get_db $i .area]}] }
        }
    }
    set bisr  [expr {$total - $arr}]
    set cells [llength [get_db insts]]
    set seq   [llength [get_db insts -if {.is_sequential == true}]]

    set fh [open $RPT_DIR/${DESIGN}_area_split.rpt w]
    puts $fh [format "%-20s %12s %12s %12s %6s" RUN TOTAL SRAM_ARRAY BISR+SPARES N_ARR]
    puts $fh [format "%-20s %12.2f %12.2f %12.2f %6d" $DESIGN $total $arr $bisr $n_arr]
    close $fh

    set csv $RPT_DIR/area_summary.csv
    set new [expr {![file exists $csv]}]
    set fh [open $csv a]
    if {$new} { puts $fh "design,top,params,total_area,sram_array_area,bisr_spares_area,cells,seq_cells" }
    puts $fh "$DESIGN,$TOP,\"$PARAMS\",$total,$arr,$bisr,$cells,$seq"
    close $fh

    puts "AREA_SPLIT $DESIGN total=$total sram_array=$arr bisr=$bisr"
} err]} {
    puts "WARNING: area split skipped ($err). Read ${DESIGN}_area.rpt by hand."
}

# Interactive use only:  set SHOW_GUI 1  before sourcing
if {[info exists SHOW_GUI] && $SHOW_GUI} { gui_show }
