#!/bin/bash
# =============================================================================
# run_genus.sh  -  Genus area sweep, one command from the BISR folder
#
#   bash run_genus.sh          all runs (shared vs dedicated, 2/4/8/16 SRAMs)
#   bash run_genus.sh p2_      only the 2-SRAM paper-setup runs
#
# Source the Cadence environment first. Edit the library path (set_db init_lib_search_path) in
# syn/genus_common.tcl if yours differs. Results: syn/reports/area_summary.csv
# (This just calls syn/run_sweep.sh.)
# =============================================================================
exec bash "$(dirname "$0")/syn/run_sweep.sh" "$@"
