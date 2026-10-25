#=============================================================================
# view.tcl  -  open a synthesized design in the Genus GUI
#
# Started by syn/view.sh (do not need to call directly). Inside Genus:
#   show shared_n4          load another design (replaces the current one)
#   report_area / report_qor / report_timing / report_power
#=============================================================================
set_db init_lib_search_path /home/cadence/install/FOUNDRY/digital/90nm/dig/lib/
read_libs slow.lib
set_db hdl_error_on_blackbox false
set_db timing_report_unconstrained false

proc show {d} {
    set nl outputs/${d}_netlist.v
    if {![file exists $nl]} {
        puts "No netlist $nl - run run_genus.sh first. Designs:"
        puts "  shared_n2 shared_n4 shared_n8 dedicated_n2 dedicated_n4 dedicated_n8"
        return
    }
    if {[llength [get_db designs]]} { delete_obj [get_db designs] }
    read_netlist $nl
    if {[file exists outputs/${d}.sdc]} { read_sdc outputs/${d}.sdc }
    gui_show
    puts ""
    puts "Loaded $d.  Schematic: right-click the top module in the hierarchy browser."
    puts "Switch design: show <name>.   Reports: report_area, report_qor, report_timing"
}

if {[info exists ::env(BISR_VIEW)]} { show $::env(BISR_VIEW) }
