# Genus synthesis (area sweep)

Same flow as the earlier `synth/` scripts (90 nm `slow.lib`, 4 ns clock,
medium effort, hierarchy kept), updated for the spare-indexed repair table and
`clustered_bisr_top`.

## Run

```
# source the Cadence environment first, then from the repository root:
bash run_genus.sh              # 6 runs
bash run_genus.sh shared       # only shared
bash run_genus.sh dedicated    # only dedicated
```

Every run black-boxes `sram_array`, so the area is **BISR logic + spare
rows only**: the part that differs between the designs.

Results: `syn/reports/area_summary.csv` (one line per run), plus per run
`_area.rpt` (per block), `_qor.rpt`, `_timing.rpt`, `_power.rpt`
(vectorless) and `_area_split.rpt`.

## Viewing results

```
bash syn/combine_reports.sh            # syn/combined/<design>_all.rpt (6 files)
gedit syn/combined/*_all.rpt &
bash syn/view.sh shared_n4             # Genus GUI with that design loaded
```
Inside the GUI session: `show dedicated_n4` switches design;
`report_area`, `report_qor`, `report_timing`, `report_power` print reports.
Schematic: right-click the top module in the hierarchy browser.

## Runs

The same two designs that `tb_bisr_compare` simulates, both with 2N spare rows:

| Run | Top | Configuration |
|---|---|---|
| `shared_n2` | `clustered_bisr_top` | 2 SRAMs, 1 controller, 1 local/SRAM + 2 global |
| `shared_n4` | `clustered_bisr_top` | 4 SRAMs, 1 controller, 1 local/SRAM + 4 global |
| `shared_n8` | `clustered_bisr_top` | 8 SRAMs, 2 controllers (4 SRAMs each), 1 local/SRAM + 4 global per controller |
| `dedicated_n2/4/8` | `dedicated_bisr_top` | one controller per SRAM, 2 local spares each |

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
