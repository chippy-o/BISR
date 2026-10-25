#!/bin/bash
# =============================================================================
# run_xcelium.sh  -  Xcelium, one command from the BISR folder
#
#   bash run_xcelium.sh compare 2          shared vs dedicated, 2 SRAMs
#   bash run_xcelium.sh compare 4 100      4 SRAMs, 100 sets per K
#   bash run_xcelium.sh compare-all 100    2, 4 and 8 SRAMs
#   bash run_xcelium.sh tests              unit + system tests
#
# Source the Cadence environment first. Logs: sim/xcelium/logs/
# (This just calls sim/xcelium/run_xcelium.sh; file list: sim/xcelium/files.f)
# =============================================================================
exec bash "$(dirname "$0")/sim/xcelium/run_xcelium.sh" "$@"
