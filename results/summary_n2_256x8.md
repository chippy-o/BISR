# BISR campaign results

rows=256, width=8, trials/point=200, seed=1, shared = 1 local + 2 global


## Fault coverage (single-cell faults, March C-)

| Fault model | Injected | Detected | Coverage (%) | Model mismatches |
|---|---|---|---|---|
| SA0 | 200 | 200 | 100.0 | 0 |
| SA1 | 200 | 200 | 100.0 | 0 |
| TF-up | 200 | 200 | 100.0 | 0 |
| TF-down | 200 | 200 | 100.0 | 0 |
| **All** | 800 | 800 | 100.0 | 0 |

## Repair metrics, averaged over k = 0..KMAX faulty rows

| N | Arch | Spares | Repair cov (%) | Mem repair success (%) | System pass (%) | Spare util (%) | BISR cycles |
|---|---|---|---|---|---|---|---|
| 2 | shared | 4 | 84.4 | 75.8 | 69.2 | 63.3 | 8678 |
| 2 | ded1 | 2 | 47.7 | 38.4 | 36.5 | 71.6 | 4502 |
| 2 | ded2 | 4 | 77.1 | 68.3 | 58.6 | 57.8 | 5031 |

## System pass rate (%) vs number of faulty rows k


**N = 2**

| Arch | k=0 | k=1 | k=2 | k=3 | k=4 | k=5 | k=6 |
|---|---|---|---|---|---|---|---|
| shared | 100.0 | 100.0 | 100.0 | 100.0 | 84.5 | 0.0 | 0.0 |
| ded1 | 100.0 | 100.0 | 55.5 | 0.0 | 0.0 | 0.0 | 0.0 |
| ded2 | 100.0 | 100.0 | 100.0 | 74.0 | 36.5 | 0.0 | 0.0 |

Reference-model mismatches across all runs: **0**
