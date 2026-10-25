#!/bin/bash
#=============================================================================
# run_xcelium.sh  -  run the BISR testbenches with Cadence Xcelium (xrun)
#
# Source the Cadence environment first (so `which xrun` works), then from
# anywhere:
#
#   bash sim/xcelium/run_xcelium.sh compare 2          # shared vs dedicated, 2 SRAMs
#   bash sim/xcelium/run_xcelium.sh compare 4 100      # 4 SRAMs, 100 sets per K
#   bash sim/xcelium/run_xcelium.sh compare 8 20 64    # 8 SRAMs, 20 sets, 64-row SRAMs
#   bash sim/xcelium/run_xcelium.sh compare-all 20     # 2, 4 and 8 SRAMs
#   bash sim/xcelium/run_xcelium.sh tests              # unit + system tests
#
# compare <N_MEM> [TRIALS=20] [ROWS=256] [SEED=1]
#
# Logs go to sim/xcelium/logs/. Every log ends with a pass/fail line:
#   tb_bisr_compare : "RESULT : ALL CHECKS PASSED"
#   unit tests      : "ALL CHECKS PASSED"
#   tb_top_scenarios: "ALL n RUN(S) MATCH THE REFERENCE MODEL"
#
# Parameters are set with -defparam on the TESTBENCH only
# (tb_bisr_compare.N_MEM, ...). Never override N_MEM globally: the dedicated
# design contains BISR instances with N_MEM = 1 on purpose.
#=============================================================================
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
XDIR="$ROOT/sim/xcelium"
LOGS="$XDIR/logs"
mkdir -p "$LOGS"
cd "$ROOT" || exit 1

if ! command -v xrun >/dev/null 2>&1; then
    echo "xrun not found - source the Cadence environment first"; exit 1
fi

# Common compile options
#   -define FAULT_INJECT : build the simulation-only fault injectors
#   -incdir rtl/include  : where bisr_defines.vh lives
XOPTS=(-define FAULT_INJECT -incdir rtl/include -f sim/xcelium/files.f)

# run <name> <top> [extra xrun args...]
run() {
    local name=$1 top=$2; shift 2
    echo "==== $name"
    xrun "${XOPTS[@]}" -top "$top" -xmlibdirname "$XDIR/xcelium.d_$name" \
         -l "$LOGS/$name.log" "$@" > /dev/null 2>&1 \
        || echo "    xrun exited with an error - see $LOGS/$name.log"
    # show the result line(s) of this run
    grep -E "RESULT :|ALL CHECKS PASSED|CHECK\(S\) FAILED|MATCH THE REFERENCE MODEL|MISMATCHED|\*E,|\*F," \
         "$LOGS/$name.log" | sed 's/^/    /'
}

compare() {
    local n=$1 trials=${2:-20} rows=${3:-256} seed=${4:-1}
    run "compare_N${n}" tb_bisr_compare \
        -defparam tb_bisr_compare.N_MEM=$n \
        -defparam tb_bisr_compare.ROWS=$rows \
        +TRIALS=$trials +SEED=$seed
    echo "    full report: $LOGS/compare_N${n}.log"
}

tests() {
    for tb in tb_sram_injector tb_march tb_logger tb_bira tb_remap; do
        run "$tb" "$tb"
    done
    run sys_shared    tb_top_scenarios -defparam tb_top_scenarios.ARCH=0
    run sys_dedicated tb_top_scenarios -defparam tb_top_scenarios.ARCH=1 \
                                       -defparam tb_top_scenarios.N_LOCAL=2 \
                                       -defparam tb_top_scenarios.FT_DEPTH=2
    run sys_clustered tb_top_scenarios -defparam tb_top_scenarios.ARCH=2 \
                                       -defparam tb_top_scenarios.N_MEM=8 \
                                       -defparam tb_top_scenarios.CLUSTER=4 \
                                       -defparam tb_top_scenarios.N_GLOBAL=4 \
                                       -defparam tb_top_scenarios.FT_DEPTH=8 \
                                       -defparam tb_top_scenarios.ROWS=64
}

case "${1:-}" in
    compare)      [ $# -ge 2 ] || { echo "usage: $0 compare <N_MEM> [TRIALS] [ROWS] [SEED]"; exit 1; }
                  shift; compare "$@" ;;
    compare-all)  for n in 2 4 8; do compare $n "${2:-20}"; done ;;
    tests)        tests ;;
    *)            sed -n '2,25p' "$0"; exit 1 ;;
esac
