#!/bin/bash
# =============================================================================
# run_genus.sh  -  Genus area sweep, one command from the BISR folder
#
#   bash run_genus.sh             6 runs: shared and dedicated at 2, 4, 8 SRAMs
#   bash run_genus.sh shared      only the 3 shared runs
#   bash run_genus.sh dedicated   only the 3 dedicated runs
#
# Source the Cadence environment first. Edit the library path (set_db init_lib_search_path) in
# syn/genus_common.tcl if yours differs. Results: syn/reports/area_summary.csv
# (This just calls syn/run_sweep.sh.)
# =============================================================================
exec bash "$(dirname "$0")/syn/run_sweep.sh" "$@"
