#!/usr/bin/env python3
"""
campaign.py - fault-injection campaigns and evaluation metrics for the
Shared BISR project (Icarus Verilog).

Two experiments:

  coverage   single-cell faults of each model (SA0, SA1, TF-up, TF-down) at
             random locations -> Fault Coverage per fault model.

  repair     k faulty rows (k = 0..KMAX) spread uniformly at random over the
             SRAMs, for each architecture:
               shared   : N_LOCAL=1, N_GLOBAL=G   (proposed)
               ded1     : dedicated, 1 local spare per SRAM (baseline)
               ded2     : dedicated, 2 local spares per SRAM (equal/greater spares)
             -> Repair Coverage, Memory Repair Success, system pass rate,
                Spare Utilization, BISR cycles.

Metric definitions (as in the paper; a "fault instance" is one faulty row,
since every injected fault is placed in a distinct row):

  Fault Coverage        = detected fault instances / injected * 100
  Repair Coverage       = repaired fault instances / injected * 100
                          (repaired = the row was given a spare in the
                           repair table)
  Memory Repair Success = faulty memories with ALL their faulty rows given a
                          spare / faulty memories * 100
  Spare Utilization     = spares assigned / spares available * 100
  System pass rate      = runs where the whole BISR (incl. VERIFY) passed

Per-memory detected/repaired counts are read by the testbench from the DUT's
own fault and repair tables, and every run is also checked against the
testbench's reference model (match=1).

Usage
  python3 campaign.py                         # paper defaults: N=2, 256x8
  python3 campaign.py --nmem 2 4 8 --rows 64  # scaling sweep
  python3 campaign.py --trials 500 --seed 7 --out results

Outputs (in --out): runs.csv (every run), summary.csv, summary.md
"""
import argparse
import csv
import os
import random
import re
import subprocess
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
RTL_DIR = os.path.join(HERE, "..", "rtl")
TB = os.path.join(HERE, "..", "tb", "tb_top_scenarios.v")
FT_NAMES = ["SA0", "SA1", "TF-up", "TF-down"]

RESULT_RE = re.compile(r"^RESULT (.*)$")


# --------------------------------------------------------------------------
# Simulation helpers
# --------------------------------------------------------------------------
def rtl_files():
    return sorted(os.path.join(RTL_DIR, f) for f in os.listdir(RTL_DIR) if f.endswith(".v"))


def build(builddir, name, arch, nmem, rows, n_local, n_global, ftd):
    vvp = os.path.join(builddir, name + ".vvp")
    cmd = ["iverilog", "-g2005", "-DFAULT_INJECT", "-I", os.path.join(RTL_DIR, "include"),
           "-s", "tb_top_scenarios",
           f"-Ptb_top_scenarios.ARCH={arch}", f"-Ptb_top_scenarios.N_MEM={nmem}",
           f"-Ptb_top_scenarios.ROWS={rows}", f"-Ptb_top_scenarios.N_LOCAL={n_local}",
           f"-Ptb_top_scenarios.N_GLOBAL={n_global}", f"-Ptb_top_scenarios.FT_DEPTH={ftd}",
           "-o", vvp] + rtl_files() + [TB]
    subprocess.run(cmd, check=True)
    return vvp


def simulate(vvp, fault_sets, path):
    """fault_sets: list of lists of (target, mem, spare, row, bit, type)."""
    with open(path, "w") as f:
        for fs in fault_sets:
            for flt in fs:
                f.write(" ".join(str(x) for x in flt) + "\n")
            f.write("9 0 0 0 0 0\n")
    out = subprocess.run(["vvp", "-n", vvp, f"+FAULTFILE={path}"],
                         check=True, capture_output=True, text=True).stdout
    results = []
    for line in out.splitlines():
        m = RESULT_RE.match(line)
        if m:
            d = {}
            for kv in m.group(1).split():
                k, v = kv.split("=")
                d[k] = [int(x) for x in v.split(",")] if k in ("lused", "inj", "det", "rep") else int(v)
            results.append(d)
    if len(results) != len(fault_sets):
        sys.exit(f"ERROR: expected {len(fault_sets)} results from {vvp}, got {len(results)}")
    return results


# --------------------------------------------------------------------------
# Fault-set generators
# --------------------------------------------------------------------------
def random_rows(rng, nmem, rows, k):
    """k faulty rows, memory chosen uniformly, rows distinct within a memory."""
    used = set()
    faults = []
    while len(faults) < k:
        m = rng.randrange(nmem)
        r = rng.randrange(rows)
        if (m, r) in used:
            continue
        used.add((m, r))
        faults.append((0, m, 0, r, rng.randrange(8), rng.randrange(4)))
    return faults


# --------------------------------------------------------------------------
# Experiments
# --------------------------------------------------------------------------
def exp_coverage(args, rng, builddir, writer):
    nmem = args.nmem[0]
    ftd = max(8, 4 * nmem)
    vvp = build(builddir, f"cov_n{nmem}", 0, nmem, args.rows, 1, args.nglobal, ftd)
    rows = []
    for ftype in range(4):
        sets = [[(0, rng.randrange(nmem), 0, rng.randrange(args.rows), rng.randrange(8), ftype)]
                for _ in range(args.trials)]
        res = simulate(vvp, sets, os.path.join(builddir, f"cov_{ftype}.flt"))
        det = sum(1 for r in res if sum(r["det"]) >= 1)
        mism = sum(1 for r in res if not r["match"])
        rows.append((FT_NAMES[ftype], len(res), det, 100.0 * det / len(res), mism))
        for fs, r in zip(sets, res):
            writer.writerow(["coverage", "shared", nmem, FT_NAMES[ftype], 1, sum(r["det"]),
                             sum(r["rep"]), r["pass"], r["unrep"], r["vfail"],
                             sum(r["lused"]) + r["gused"], r["cycles"], r["match"]])
    return rows


def configs(nglobal):
    #        name     arch nlocal nglobal
    return [("shared", 0, 1, nglobal),
            ("ded1",   1, 1, 0),
            ("ded2",   1, 2, 0)]


def exp_repair(args, rng, builddir, writer):
    summary = []
    for nmem in args.nmem:
        ftd = max(8, 4 * nmem)
        kmax = args.kmax if args.kmax is not None else 2 * nmem + 2
        # same fault sets for every architecture (paired comparison)
        sets_by_k = {k: [random_rows(rng, nmem, args.rows, k) for _ in range(args.trials)]
                     for k in range(kmax + 1)}
        for name, arch, nl, ng in configs(args.nglobal):
            vvp = build(builddir, f"{name}_n{nmem}", arch, nmem, args.rows, nl, ng, ftd)
            avail = nmem * nl + ng
            all_sets, keys = [], []
            for k in range(kmax + 1):
                all_sets += sets_by_k[k]
                keys += [k] * len(sets_by_k[k])
            res = simulate(vvp, all_sets, os.path.join(builddir, f"{name}_n{nmem}.flt"))
            acc = defaultdict(lambda: defaultdict(int))
            for k, r in zip(keys, res):
                inj = sum(r["inj"])
                rep = sum(min(a, b) for a, b in zip(r["rep"], r["inj"]))
                fmem = sum(1 for x in r["inj"] if x > 0)
                okmem = sum(1 for a, b in zip(r["rep"], r["inj"]) if a > 0 and a >= b)
                used = sum(r["lused"]) + r["gused"]
                for key in (k, "all"):
                    a = acc[key]
                    a["runs"] += 1
                    a["inj"] += inj
                    a["det"] += sum(r["det"])
                    a["rep"] += rep
                    a["fmem"] += fmem
                    a["okmem"] += okmem
                    a["pass"] += r["pass"]
                    a["used"] += used
                    a["avail"] += avail
                    a["cyc"] += r["cycles"]
                    a["mism"] += 0 if r["match"] else 1
                writer.writerow(["repair", name, nmem, "mixed", inj, sum(r["det"]), rep,
                                 r["pass"], r["unrep"], r["vfail"], used, r["cycles"], r["match"]])
            for key in list(range(kmax + 1)) + ["all"]:
                a = acc[key]
                pct = lambda n, d: (100.0 * n / d) if d else float("nan")
                summary.append({
                    "nmem": nmem, "arch": name, "spares": avail, "k": key, "runs": a["runs"],
                    "fault_cov": pct(a["det"], a["inj"]),
                    "repair_cov": pct(a["rep"], a["inj"]),
                    "mem_success": pct(a["okmem"], a["fmem"]),
                    "sys_pass": pct(a["pass"], a["runs"]),
                    "spare_util": pct(a["used"], a["avail"]),
                    "cycles": a["cyc"] / a["runs"],
                    "mismatch": a["mism"],
                })
    return summary


# --------------------------------------------------------------------------
def fmt(x):
    if isinstance(x, float):
        return "-" if x != x else f"{x:.1f}"
    return str(x)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--nmem", type=int, nargs="+", default=[2], help="SRAM counts to sweep")
    ap.add_argument("--rows", type=int, default=256)
    ap.add_argument("--nglobal", type=int, default=2, help="global spares of the shared design")
    ap.add_argument("--trials", type=int, default=200, help="fault sets per point")
    ap.add_argument("--kmax", type=int, default=None, help="max faulty rows (default 2N+2)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default="results")
    ap.add_argument("--skip-coverage", action="store_true")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    builddir = os.path.join(args.out, "build")
    os.makedirs(builddir, exist_ok=True)
    rng = random.Random(args.seed)

    with open(os.path.join(args.out, "runs.csv"), "w", newline="") as fr:
        w = csv.writer(fr)
        w.writerow(["experiment", "arch", "n_mem", "fault_model", "injected", "detected",
                    "repaired", "pass", "unrep", "vfail", "spares_used", "cycles", "match"])
        cov = [] if args.skip_coverage else exp_coverage(args, rng, builddir, w)
        summ = exp_repair(args, rng, builddir, w)

    cols = ["nmem", "arch", "spares", "k", "runs", "fault_cov", "repair_cov",
            "mem_success", "sys_pass", "spare_util", "cycles", "mismatch"]
    with open(os.path.join(args.out, "summary.csv"), "w", newline="") as fs:
        w = csv.DictWriter(fs, fieldnames=cols)
        w.writeheader()
        w.writerows(summ)

    md = [f"# BISR campaign results\n",
          f"rows={args.rows}, width=8, trials/point={args.trials}, seed={args.seed}, "
          f"shared = 1 local + {args.nglobal} global\n"]
    if cov:
        md += ["\n## Fault coverage (single-cell faults, March C-)\n",
               "| Fault model | Injected | Detected | Coverage (%) | Model mismatches |",
               "|---|---|---|---|---|"]
        md += [f"| {n} | {i} | {d} | {c:.1f} | {m} |" for n, i, d, c, m in cov]
        ti, td = sum(r[1] for r in cov), sum(r[2] for r in cov)
        md.append(f"| **All** | {ti} | {td} | {100.0*td/ti:.1f} | {sum(r[4] for r in cov)} |")
    md += ["\n## Repair metrics, averaged over k = 0..KMAX faulty rows\n",
           "| N | Arch | Spares | Repair cov (%) | Mem repair success (%) | System pass (%) | Spare util (%) | BISR cycles |",
           "|---|---|---|---|---|---|---|---|"]
    for s in summ:
        if s["k"] == "all":
            md.append(f"| {s['nmem']} | {s['arch']} | {s['spares']} | {fmt(s['repair_cov'])} | "
                      f"{fmt(s['mem_success'])} | {fmt(s['sys_pass'])} | {fmt(s['spare_util'])} | "
                      f"{s['cycles']:.0f} |")
    md += ["\n## System pass rate (%) vs number of faulty rows k\n"]
    for nmem in args.nmem:
        ks = sorted({s["k"] for s in summ if s["nmem"] == nmem and s["k"] != "all"})
        md += [f"\n**N = {nmem}**\n", "| Arch | " + " | ".join(f"k={k}" for k in ks) + " |",
               "|---|" + "---|" * len(ks)]
        for name, *_ in configs(args.nglobal):
            row = {s["k"]: s for s in summ if s["nmem"] == nmem and s["arch"] == name}
            md.append(f"| {name} | " + " | ".join(fmt(row[k]["sys_pass"]) for k in ks) + " |")
    total_mism = sum(s["mismatch"] for s in summ if s["k"] == "all") + sum(r[4] for r in cov)
    md.append(f"\nReference-model mismatches across all runs: **{total_mism}**\n")
    with open(os.path.join(args.out, "summary.md"), "w") as f:
        f.write("\n".join(md))
    print("\n".join(md))


if __name__ == "__main__":
    main()
