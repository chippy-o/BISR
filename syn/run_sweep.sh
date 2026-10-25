#!/bin/bash
#=============================================================================
# run_sweep.sh  -  Genus area sweep: shared vs clustered vs dedicated
#
#   cd syn && bash run_sweep.sh            # all runs
#   bash run_sweep.sh p2_                  # only runs whose name starts p2_
#
# Source the Cadence environment first (so `which genus` works).
# Every run black-boxes sram_array, so area = BISR logic + spare rows.
# Results: reports/area_summary.csv (one line per run) + per-run reports.
#
# Runs
#   p2_*   original paper setup with the new RTL: N=2, 8-entry fault tables
#   sh_nN  shared, one controller, N_GLOBAL = N, FT_DEPTH = 2N (= its spares)
#   cl_nN  clustered, 4 SRAMs per controller, 4 global spares per cluster
#   d1_nN  dedicated, 1 local spare per SRAM, FT_DEPTH = 1
#   d2_nN  dedicated, 2 local spares per SRAM, FT_DEPTH = 2 (same 2N spares
#          as sh_nN / cl_nN)
#=============================================================================
cd "$(dirname "$0")" || exit 1
mkdir -p logs runs reports
FILTER="$1"

# name | top | params
RUNS=(
"p2_shared_ft8|shared_bisr_top|{N_MEM 2} {N_LOCAL 1} {N_GLOBAL 2} {FT_DEPTH 8} {SPARE_GATING 1}"
"p2_ded1_ft8|dedicated_bisr_top|{N_MEM 2} {N_LOCAL 1} {FT_DEPTH 8} {SPARE_GATING 1}"
"p2_ded2_ft8|dedicated_bisr_top|{N_MEM 2} {N_LOCAL 2} {FT_DEPTH 8} {SPARE_GATING 1}"
)
for N in 2 4 8 16; do
    RUNS+=("sh_n$N|shared_bisr_top|{N_MEM $N} {N_LOCAL 1} {N_GLOBAL $N} {FT_DEPTH $((2*N))} {SPARE_GATING 1}")
    if [ $N -ge 8 ]; then
        RUNS+=("cl_n$N|clustered_bisr_top|{N_MEM $N} {CLUSTER 4} {N_LOCAL 1} {N_GLOBAL 4} {FT_DEPTH 8} {SPARE_GATING 1}")
    fi
    RUNS+=("d1_n$N|dedicated_bisr_top|{N_MEM $N} {N_LOCAL 1} {FT_DEPTH 1} {SPARE_GATING 1}")
    RUNS+=("d2_n$N|dedicated_bisr_top|{N_MEM $N} {N_LOCAL 2} {FT_DEPTH 2} {SPARE_GATING 1}")
done

for r in "${RUNS[@]}"; do
    IFS='|' read -r name top params <<< "$r"
    [ -n "$FILTER" ] && [[ "$name" != $FILTER* ]] && continue
    cat > runs/syn_$name.tcl <<EOF
set DESIGN        $name
set TOP           $top
set PARAMS        {{ROWS 256} {WIDTH 8} $params}
set BLACKBOX_SRAM 1
source genus_common.tcl
EOF
    echo "==== $name"
    genus -batch -files runs/syn_$name.tcl -log logs/$name || echo "!!!! $name failed, see logs/$name.log"
done

echo
echo "==== reports/area_summary.csv"
column -s, -t < reports/area_summary.csv 2>/dev/null || cat reports/area_summary.csv
