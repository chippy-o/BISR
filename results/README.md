# results/

| File | What it is |
|---|---|
| `tb_bisr_compare_N2_sample.log` | Sample report of `tb_bisr_compare` (2 SRAMs, 3 sets per K) |
| `summary_n2_256x8.*` | `campaign.py`, 2 SRAMs, 256x8, shared 1L+2G vs dedicated 1L / 2L. Repair algorithm is unchanged, so these still hold. |
| `summary_sweep_64rows.*` | `campaign.py`, 2/4/8 SRAMs (64 rows), fixed pool of 2 global spares |
| `yosys_area_newrtl.csv` | Yosys gate-equivalent estimate, **current RTL** (spare-indexed repair table, clustered top) |
| `yosys_area_oldrtl_*.csv` | Yosys estimate of the **original RTL** (kept for reference only) |

Yosys numbers are generic-gate estimates for trends; use Genus (`syn/run_sweep.sh`) for paper numbers.
