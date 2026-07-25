#!/usr/bin/env python3
"""plot_cpi.py -- plot measured CPI and branch-mispredict rates.

Reads the CSV from `scripts/run_benchmarks.sh --csv` and writes two figures:
CPI per benchmark per predictor mode, and mispredict rate per benchmark per
mode. Plot data comes straight from the measured counters.

    python3 plot_cpi.py results.csv --outdir docs/results
"""
import argparse
import csv
import os
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

MODES = ["off", "bimodal", "gshare"]
LABEL = {"off": "no prediction", "bimodal": "bimodal", "gshare": "gshare"}


def load(path):
    d = defaultdict(dict)
    with open(path) as f:
        for r in csv.DictReader(f):
            d[r["benchmark"]][r["mode"]] = r
    return d


def bars(ax, benches, series, ylabel, title):
    n, w = len(MODES), 0.26
    for i, mode in enumerate(MODES):
        xs = [j + (i - (n - 1) / 2) * w for j in range(len(benches))]
        ax.bar(xs, [series[b][mode] for b in benches], width=w, label=LABEL[mode])
    ax.set_xticks(range(len(benches)))
    ax.set_xticklabels([b.replace("bench_", "") for b in benches],
                       rotation=30, ha="right")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.grid(axis="y", alpha=0.3)
    ax.legend()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv")
    ap.add_argument("--outdir", default=".")
    a = ap.parse_args()

    data = load(a.csv)
    benches = sorted(b for b in data if all(m in data[b] for m in MODES))
    os.makedirs(a.outdir, exist_ok=True)

    cpi = {b: {m: float(data[b][m]["cpi"]) for m in MODES} for b in benches}
    fig, ax = plt.subplots(figsize=(9, 4.2))
    bars(ax, benches, cpi, "cycles per instruction",
         "Measured CPI by branch-predictor mode (Verilator simulation)")
    fig.tight_layout()
    p1 = os.path.join(a.outdir, "cpi.png")
    fig.savefig(p1, dpi=140)

    mis = {}
    for b in benches:
        br = int(data[b]["off"]["branches"])
        if br == 0:
            continue
        mis[b] = {m: 100.0 * int(data[b][m]["mispredicts"]) / br for m in MODES}
    bb = [b for b in benches if b in mis]
    fig2, ax2 = plt.subplots(figsize=(9, 4.2))
    bars(ax2, bb, mis, "mispredicted branches (%)",
         "Measured conditional-branch mispredict rate")
    fig2.tight_layout()
    p2 = os.path.join(a.outdir, "mispredict.png")
    fig2.savefig(p2, dpi=140)

    print(f"wrote {p1}\nwrote {p2}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
