#!/bin/bash
#=============================================================================
# run_sweep.sh  -  Genus area: SHARED vs DEDICATED BISR at 2, 4 and 8 SRAMs
#
#   bash run_sweep.sh              all 6 runs
#   bash run_sweep.sh shared       only the 3 shared runs
#   bash run_sweep.sh dedicated    only the 3 dedicated runs
#   bash run_sweep.sh shared_n4    one run
#
# Source the Cadence environment first (so `which genus` works).
# Every run black-boxes sram_array, so area = BISR logic + spare rows.
# Results: reports/area_summary.csv (one line per run) + per-run reports.
#
# The 6 runs are exactly the two designs simulated by tb_bisr_compare:
#   shared_nN     clustered_bisr_top, up to 4 SRAMs per controller,
#                 1 local spare per SRAM + 1 global spare per SRAM (pool)
#                 N=2: 1 controller   N=4: 1 controller   N=8: 2 controllers
#   dedicated_nN  dedicated_bisr_top, one controller per SRAM,
#                 2 local spares per SRAM
#   Both have 2N spare rows. Fault tables are sized to the spare count.
#=============================================================================
cd "$(dirname "$0")" || exit 1
mkdir -p logs runs reports
FILTER="${1:-}"

# name | top | params
RUNS=()
for N in 2 4 8; do
    CL=$(( N < 4 ? N : 4 ))              # SRAMs per shared controller
    RUNS+=("shared_n$N|clustered_bisr_top|{N_MEM $N} {CLUSTER $CL} {N_LOCAL 1} {N_GLOBAL $CL} {FT_DEPTH $((2*CL))} {SPARE_GATING 1}")
done
for N in 2 4 8; do
    RUNS+=("dedicated_n$N|dedicated_bisr_top|{N_MEM $N} {N_LOCAL 2} {FT_DEPTH 2} {SPARE_GATING 1}")
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
bash combine_reports.sh                # one file per design in syn/combined/

echo
echo "==== reports/area_summary.csv"
column -s, -t < reports/area_summary.csv 2>/dev/null || cat reports/area_summary.csv
