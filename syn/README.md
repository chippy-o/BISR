# Genus synthesis (area sweep)

Same flow as the earlier `synth/` scripts (90 nm `slow.lib`, 4 ns clock,
medium effort, hierarchy kept), updated for the spare-indexed repair table and
`clustered_bisr_top`.

## Run

```
# source the Cadence environment first, then from the repository root:
cd syn
bash run_sweep.sh          # all 17 runs
bash run_sweep.sh p2_      # only the N=2 paper-setup runs
```

Every sweep run black-boxes `sram_array`, so the area is **BISR logic + spare
rows only**: the part that differs between the architectures. The SRAM arrays
are identical in every design.

Results: `reports/area_summary.csv` (one line per run), plus per run
`_area.rpt` (per block), `_qor.rpt`, `_timing.rpt` (real critical path now),
`_power.rpt` (vectorless) and `_area_split.rpt`.

## Runs

| Name | Top | Configuration | Purpose |
|---|---|---|---|
| `p2_shared_ft8`, `p2_ded1_ft8`, `p2_ded2_ft8` | shared / dedicated | N = 2, 8-entry fault tables | Original paper setup, new RTL |
| `sh_nN` (N = 2, 4, 8, 16) | `shared_bisr_top` | 1 local + N global, FT_DEPTH = 2N | One controller for all SRAMs |
| `cl_nN` (N = 8, 16) | `clustered_bisr_top` | clusters of 4, 4 global per cluster, FT_DEPTH = 8 | Bounded sharing domain |
| `d1_nN` | `dedicated_bisr_top` | 1 local, FT_DEPTH = 1 | Baseline |
| `d2_nN` | `dedicated_bisr_top` | 2 local, FT_DEPTH = 2 | Same 2N spares as `sh_nN` / `cl_nN` |

Fault tables are sized to each design's spare count: a single-pass BIRA can
never repair more rows than it has spares, and overflow already flags
"unrepairable", so a deeper table only adds area.

## Full-design runs (arrays as flip-flops)

For the old-style numbers (whole design including the arrays), write a run
script with `set BLACKBOX_SRAM 0` and compare the `BISR+SPARES` column of
`_area_split.rpt`, not the total.

## If `elaborate -parameters` errors

Some Genus versions want the values in declaration order instead of
`{name value}` pairs. Send the log line and adjust `PARAMS` accordingly.
