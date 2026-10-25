#!/bin/bash
#=============================================================================
# view.sh  -  open one synthesized design in the Genus GUI
#
#   bash syn/view.sh shared_n4        (from the BISR folder, Cadence sourced)
#
# Designs: shared_n2 shared_n4 shared_n8 dedicated_n2 dedicated_n4 dedicated_n8
# Inside Genus, type  show dedicated_n4  to switch to another design.
# For several designs at once, run this in several terminal windows
# (each one uses a Genus licence).
#=============================================================================
cd "$(dirname "$0")" || exit 1          # -> syn/
mkdir -p logs
export BISR_VIEW="${1:-shared_n2}"
exec genus -files view.tcl -log "logs/view_${BISR_VIEW}"
