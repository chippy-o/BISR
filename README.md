# Shared BISR with Local and Global Redundancy

RTL and verification for **"A Shared BISR Architecture with Local and Global
Redundancy for Efficient SRAM Test and Repair"** (S. Tarun, C G S S Ratna Sashank,
VIT Vellore).

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
| `rtl/fault_logger.v` | 8-entry fault table with row merge and overflow |
| `rtl/bira.v` | Single-pass local-then-global redundancy analysis |
| `rtl/repair_table.v` | Final spare assignments |
| `rtl/remap_unit.v` | Address CAM, spare steering, spare enables |
| `rtl/bisr_ctrl_fsm.v` | Top-level sequencer |
| `rtl/shared_bisr_top.v` | **Proposed design** |
| `rtl/dedicated_bisr_top.v` | **Baseline**: one full BISR per SRAM, local spares only |
| `tb/tb_*.v` | Unit testbenches + system testbench with reference model |
| `sim/Makefile` | Icarus Verilog runs |
| `sim/modelsim/*.do` | ModelSim / Questa batch and GUI scripts |
| `sim/rtl_files.f` | Synthesisable file list |

## Parameters (`shared_bisr_top`)

| Parameter | Default | Meaning |
|---|---|---|
| `N_MEM` | 2 | SRAMs served by the controller |
| `ROWS`, `WIDTH` | 256, 8 | SRAM size |
| `N_LOCAL` | 1 | Local spare rows per SRAM |
| `N_GLOBAL` | 2 | Shared global spare rows (0 = none) |
| `FT_DEPTH` | 8 | Fault-table / repair-table entries |
| `SPARE_GATING` | 1 | 1 = selective spare activation, 0 = all spares clocked (power reference) |

`dedicated_bisr_top` has the same ports. With `N_LOCAL=1` it is the dedicated
baseline; with `N_LOCAL=2` it is the equal-total-spares baseline.

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
make shared ROWS=64 NMEM=4  # other sizes
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
