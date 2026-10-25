#!/bin/bash
#=============================================================================
# combine_reports.sh  -  one report file per design
#
#   bash syn/combine_reports.sh        (from the BISR folder, after run_genus.sh)
#
# For each of the 6 designs, appends every Genus report (qor, area, timing,
# power, gates, area_split, check) into one file:
#   syn/combined/<design>_all.rpt
# run_genus.sh also calls this automatically at the end.
#=============================================================================
cd "$(dirname "$0")" || exit 1          # -> syn/
mkdir -p combined

for d in shared_n2 shared_n4 shared_n8 dedicated_n2 dedicated_n4 dedicated_n8; do
    out="combined/${d}_all.rpt"
    {
        echo "##########################################################################"
        echo "#  DESIGN : ${d}"
        echo "##########################################################################"
        for r in qor area timing power gates area_split check; do
            f="reports/${d}_${r}.rpt"
            echo
            echo "=========================================================================="
            echo "  ${d}  -  ${r} report   (syn/${f})"
            echo "=========================================================================="
            if [ -f "${f}" ]; then
                cat "${f}"
            else
                echo "  (missing)"
            fi
        done
    } > "${out}"
    echo "written syn/${out}"
done
