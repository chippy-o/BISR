# Shared BISR with Local and Global Redundancy

RTL and verification for **"A Shared BISR Architecture with Local and Global
Redundancy for Efficient SRAM Test and Repair"** (S. Tarun, C G S S Ratna Sashank,
VIT Vellore).

## Quick start (no paths to set)

```
git clone https://github.com/chippy-o/BISR.git
cd BISR
```

| Tool | Do this | Then |
|---|---|---|
| **ModelSim** | `File > Change Directory...` to the `BISR` folder, then `do run.do` in the Transcript | `compare 2` / `compare 4 10 64` / `compare 8 10 64` / `tests` |
| **Xcelium** | source Cadence setup | `bash run_xcelium.sh compare 2` (or `compare-all 100`, `tests`) |
| **Genus** | source Cadence setup | `bash run_genus.sh` (area sweep, results in `syn/reports/area_summary.csv`) |

`compare <N_MEM> [TRIALS] [ROWS]` runs `tb_bisr_compare`: shared vs dedicated
BISR on identical faults, ending in `RESULT : ALL CHECKS PASSED` and the repair
success rate of both designs. Reports are saved as `compare_N<n>.log`.

One BISR controller serves several SRAMs. Each SRAM has its own **local** spare
row(s); a small **global** pool of spare rows can be used by whichever SRAM runs
out of local spares.

```
bisr_ctrl_fsm ─┬─> march_cminus ─> fault_logger ─> bira ─> repair_table
               │                                              │
               └──────────────────── remap_unit <─────────────┘
                                         │
   func ports ─> port mux ─> sram_wrapper[0..N-1] <──> global spare pool
```

Repair sequence: `IDLE → CLEAR → TEST → ANALYZE → LOAD → VERIFY → DONE`

1. **TEST** – March C- (10N) on every SRAM, one after another; each failing row is logged.
2. **ANALYZE** – BIRA gives each faulty row the next free local spare, else the next free global spare, else marks the system unrepairable.
3. **LOAD / VERIFY** – remapping is switched on and March C- runs again through it. Any fail means the repair did not work.
4. **DONE** – the memories are usable; accesses to repaired rows go to their spares.

## Repository layout

| Path | Contents |
|---|---|
| `rtl/include/bisr_defines.vh` | Fault-type and target codes |
| `rtl/sram_array.v` | Behavioural storage array (black-box / macro candidate) |
| `rtl/fault_injector.v` | **Simulation only.** SA0, SA1, TF-up, TF-down injection |
| `rtl/spare_icg.v` | Clock gate for selective spare activation |
| `rtl/spare_row_bank.v` | K spare rows with per-row ports and gating (local spares and global pool) |
| `rtl/sram_wrapper.v` | Main array + local spares + read mux + registered read port |
| `rtl/march_cminus.v` | Shared March C- MBIST controller |
| `rtl/fault_logger.v` | `FT_DEPTH`-entry fault table with row merge and overflow |
| `rtl/bira.v` | Single-pass local-then-global redundancy analysis |
| `rtl/repair_table.v` | Spare-indexed repair table: one slot per local spare (row) and per global spare (owner + row) |
| `rtl/remap_unit.v` | Address compare (own local slots + global slots), spare steering, spare enables |
| `rtl/bisr_ctrl_fsm.v` | Top-level sequencer |
| `rtl/shared_bisr_top.v` | **Proposed design** |
| `rtl/dedicated_bisr_top.v` | **Baseline**: one full BISR per SRAM, local spares only |
| `rtl/clustered_bisr_top.v` | **Scalable version**: SRAMs in clusters of `CLUSTER`, one shared controller + global pool per cluster |
| `tb/tb_bisr_compare.v` | **Shared vs dedicated report**: same faults into both designs, readable per-test output, repair success rate |
| `tb/tb_*.v` | Unit testbenches + system testbench with reference model |
| `sim/Makefile` | Icarus Verilog runs |
| `sim/modelsim/*.do` | ModelSim / Questa batch and GUI scripts |
| `sim/xcelium/` | Xcelium file list (`files.f`) and run script (`run_xcelium.sh`) |
| `sim/rtl_files.f` | Synthesisable file list |
| `sim/campaign.py` | Fault-injection campaigns: fault coverage, repair coverage, memory repair success, spare utilization |
| `syn/` | Genus area sweep (shared / clustered / dedicated, N = 2..16) |
| `results/` | Campaign summaries and Yosys area estimates |

## Parameters (`shared_bisr_top`)

| Parameter | Default | Meaning |
|---|---|---|
| `N_MEM` | 2 | SRAMs served by the controller |
| `ROWS`, `WIDTH` | 256, 8 | SRAM size |
| `N_LOCAL` | 1 | Local spare rows per SRAM |
| `N_GLOBAL` | 2 | Shared global spare rows (0 = none) |
| `FT_DEPTH` | `N_MEM*N_LOCAL + N_GLOBAL` | Fault-table entries (= total spares; a single-pass BIRA cannot repair more rows than it has spares, and overflow already flags "unrepairable"). The repair table is sized by the spares, not by `FT_DEPTH`. |
| `SPARE_GATING` | 1 | 1 = selective spare activation, 0 = all spares clocked (power reference) |

`dedicated_bisr_top` has the same ports. With `N_LOCAL=1` it is the dedicated
baseline; with `N_LOCAL=2` it is the equal-total-spares baseline. Its
`FT_DEPTH` (per SRAM) defaults to `N_LOCAL`.

`clustered_bisr_top` has the same ports plus `CLUSTER` (SRAMs per controller,
default 4). `N_GLOBAL` and `FT_DEPTH` are per cluster (defaults `CLUSTER` and
`CLUSTER*N_LOCAL + N_GLOBAL`). `N_MEM` must be a multiple of `CLUSTER`.
`CLUSTER = N_MEM` gives the single shared controller.

### Scaling rule

The global pool grows with the number of SRAMs (`N_GLOBAL = N_MEM` for one
controller, `N_GLOBAL = CLUSTER` per cluster), so the shared design always has
the same 2N spares as the 2-local-spare dedicated baseline. Remap compare
logic is `N_MEM*N_LOCAL + N_MEM*N_GLOBAL` comparators per controller; with the
pool growing as N this is O(N^2) for one controller and O(N) with clusters.

## Shared vs dedicated report (`tb_bisr_compare`)

Builds both designs for the same SRAMs and the same spare count
(dedicated: 2 local spares per SRAM; shared: 1 local per SRAM + a global pool
of 1 per SRAM, at most 4 SRAMs per controller), injects identical faults,
checks both against a reference model, and read/write-checks every row after
repair. Prints 8 directed tests, a random-campaign table (repair rate per
number of faulty rows K) and a summary with repair success rate and repair
coverage.

```
cd sim/modelsim && vsim -c -do run_compare.do        # N = 2, 4, 8
cd sim && make compare NMEM=4 TRIALS=50              # Icarus
```
Plusargs: `+TRIALS=<n>` `+SEED=<s>` `+VERBOSE` (print every random run).

## Xcelium

```
# source the Cadence environment, then from the repository root:
bash sim/xcelium/run_xcelium.sh compare 2          # shared vs dedicated, 2 SRAMs
bash sim/xcelium/run_xcelium.sh compare-all 100    # 2, 4, 8 SRAMs, 100 sets per K
bash sim/xcelium/run_xcelium.sh tests              # unit + system tests
```
File list: `sim/xcelium/files.f`. Logs: `sim/xcelium/logs/`.
Testbench parameters are set with `-defparam tb_bisr_compare.N_MEM=...`
(never a global N_MEM override: the dedicated design uses N_MEM = 1 inside).

## Running the simulations

**ModelSim / Questa**
```
cd sim/modelsim
vsim -c -do run_all.do      # everything, batch mode
vsim -do run_gui.do         # shared design with waveforms
```

**Icarus Verilog**
```
cd sim
make all                    # unit tests, three architectures, random campaigns
make shared ROWS=64 NMEM=4 FTD=8 NGLB=4     # other sizes
make clustered NMEM=8 CLUS=4 NGLB=4 FTD=8     # clustered design
```

Every testbench is self-checking and ends with `ALL CHECKS PASSED` or
`ALL n RUN(S) MATCH THE REFERENCE MODEL`.

### System testbench (`tb_top_scenarios`)

Contains a behavioural reference model of the repair algorithm and checks the
DUT against it on every run (pass, unrepairable, overflow, verify fail, fault
count, spares used). After a successful repair it also writes and reads every
row of every SRAM through the functional ports.

| Mode | How | Use |
|---|---|---|
| Directed | no plusargs | Scenarios S1–S8 |
| Random | `+RANDOM=<n> +SEED=<s>` | Random fault sets around the repair limit |
| Fault file | `+FAULTFILE=<path>` | One run with faults from a file (Python campaigns) |

Fault-file format, one fault per line: `target mem spare row bit type`
(target 0 main / 1 local spare / 2 global spare; type 0 SA0 / 1 SA1 / 2 TF-up / 3 TF-down).

Every run prints a `RESULT ...` line for scripts to parse.

### Directed scenarios

| | Faults | Shared (1L + 2G) | Dedicated (1L) | Dedicated (2L) |
|---|---|---|---|---|
| S1 | none | pass | pass | pass |
| S2 | 1 row in each SRAM | pass | pass | pass |
| S3 | 3 rows in SRAM0 | **pass** (1 local + 2 global) | fail | fail |
| S4 | 4 rows in SRAM0 | fail | fail | fail |
| S5 | 3 bad bits in one row | pass (1 spare) | pass | pass |
| S6 | used local spare is faulty | verify fail | verify fail | verify fail |
| S7 | 9 faulty rows | overflow | fail | fail |
| S8 | 2 rows in each SRAM | **pass** | fail | pass |

## Design decisions

* **Read latency:** the wrapper registers read data (1 cycle), like a synchronous SRAM macro.
* **One MBIST for all memories:** SRAMs are tested sequentially with one comparator, which keeps the shared controller small. Test time grows with `N_MEM`.
* **Global pool ports:** every spare row has its own port. A global row belongs to at most one SRAM, so two SRAMs can use their global spares in the same cycle without conflict.
* **Fault table = repair table index:** BIRA writes entry *i* of the repair table from entry *i* of the fault table.
* **Selective spare activation:** spare rows are clock-gated and their read data forced to 0 until assigned. Replace `spare_icg` with the library ICG cell for synthesis.

## Known limitations

* Row repair only (no column spares).
* Spare rows are not tested before allocation; a faulty spare is only detected in VERIFY and is not recovered from.
* At most `FT_DEPTH` faulty rows can be logged.
* Single-pass allocation in fault-table order.
* Solid 0/1 data background: intra-word coupling faults are not targeted.

## Synthesis notes

* Do **not** define `FAULT_INJECT`; use `sim/rtl_files.f`.
* Black-box `sram_array` (or replace it with a macro) so area reflects the BISR logic.
* Map `spare_icg` to the library clock-gating cell.
* For the power comparison, synthesise once with `SPARE_GATING=1` and once with `0`, and annotate switching activity (SAIF) from simulation.
