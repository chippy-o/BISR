#=============================================================================
# genus_sweep.tcl - area sweep: Shared BISR vs Dedicated BISR, N = 2, 4, 8
#                   (Genus, 90nm slow.lib lab flow)
#
# Run from the repository root:
#     genus -files syn/genus_sweep.tcl -log syn/out/genus.log
#
# Edit LIB_PATH / LIB_NAME to match your lab template (90nm slow.lib).
# sram_array is NOT read, so every main storage array is a black box and the
# area reported is BISR logic + spare rows only (the part that differs
# between architectures). The SRAM area itself is identical for both.
#
# Output: syn/out/<cfg>_area.rpt, <cfg>_gates.rpt, <cfg>_hier.rpt
#         syn/out/area_summary.csv  (one line per configuration)
#=============================================================================

set LIB_PATH  "/path/to/your/lib/dir"      ;# <-- EDIT
set LIB_NAME  "slow.lib"                    ;# <-- EDIT if different
set CLK_NS    10.0                          ;# 100 MHz
set ROWS      256
set WIDTH     8
set OUT       "syn/out"

file mkdir $OUT

# name  top  N_MEM  N_LOCAL  N_GLOBAL  FT_DEPTH
#
# FT_DEPTH is sized to each design's spare count (N*N_LOCAL + N_GLOBAL for
# shared, N_LOCAL per dedicated instance): a single-pass BIRA can never repair
# more rows than it has spares, and fault-table overflow already flags
# "unrepairable", so deeper tables add area without adding repair capability.
# The *_ft8 rows reproduce the original N=2 setup (8-entry tables everywhere).
set CFGS {
    {shared_n2_ft8 shared_bisr_top    2 1 2  8}
    {ded1_n2_ft8   dedicated_bisr_top 2 1 0  8}
    {ded2_n2_ft8   dedicated_bisr_top 2 2 0  8}
    {shared_n2     shared_bisr_top    2 1 2  4}
    {ded1_n2       dedicated_bisr_top 2 1 0  1}
    {ded2_n2       dedicated_bisr_top 2 2 0  2}
    {shared_n4     shared_bisr_top    4 1 2  6}
    {ded1_n4       dedicated_bisr_top 4 1 0  1}
    {ded2_n4       dedicated_bisr_top 4 2 0  2}
    {shared_n8     shared_bisr_top    8 1 2 10}
    {ded1_n8       dedicated_bisr_top 8 1 0  1}
    {ded2_n8       dedicated_bisr_top 8 2 0  2}
}

# Synthesisable RTL (no fault_injector, no sram_array -> black box)
set RTL {
    rtl/spare_icg.v rtl/spare_row_bank.v rtl/sram_wrapper.v rtl/march_cminus.v
    rtl/fault_logger.v rtl/bira.v rtl/repair_table.v rtl/remap_unit.v
    rtl/bisr_ctrl_fsm.v rtl/shared_bisr_top.v rtl/dedicated_bisr_top.v
}

set_db init_lib_search_path $LIB_PATH
set_db library $LIB_NAME
set_db init_hdl_search_path "rtl rtl/include"
set_db hdl_error_on_blackbox false      ;# sram_array stays a black box

set csv [open "$OUT/area_summary.csv" w]
puts $csv "config,top,n_mem,n_local,n_global,ft_depth,cell_area,cells,seq_cells"

foreach cfg $CFGS {
    lassign $cfg name top nmem nloc nglb ftd
    puts "\n==================== $name ===================="

    if {[llength [get_db designs]]} { delete_obj [get_db designs] }

    read_hdl -v2001 $RTL

    if {$top eq "shared_bisr_top"} {
        set params [list [list N_MEM $nmem] [list ROWS $ROWS] [list WIDTH $WIDTH] \
                         [list N_LOCAL $nloc] [list N_GLOBAL $nglb] [list FT_DEPTH $ftd] \
                         [list SPARE_GATING 1]]
    } else {
        set params [list [list N_MEM $nmem] [list ROWS $ROWS] [list WIDTH $WIDTH] \
                         [list N_LOCAL $nloc] [list FT_DEPTH $ftd] [list SPARE_GATING 1]]
    }
    elaborate $top -parameters $params

    create_clock -name clk -period $CLK_NS [get_ports clk]
    set_input_delay  0.0 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
    set_output_delay 0.0 -clock clk [all_outputs]

    syn_generic
    syn_map
    syn_opt

    report_area                 > "$OUT/${name}_area.rpt"
    report_gates                > "$OUT/${name}_gates.rpt"
    report_area -depth 4        > "$OUT/${name}_hier.rpt"
    report_timing               > "$OUT/${name}_timing.rpt"

    set d [get_db designs]
    set area  [get_db $d .area]
    set cells [llength [get_db insts]]
    set seq   [llength [get_db insts -if {.is_sequential == true}]]
    puts $csv "$name,$top,$nmem,$nloc,$nglb,$ftd,$area,$cells,$seq"
    flush $csv
}

close $csv
puts "\nArea summary written to $OUT/area_summary.csv"
exit
