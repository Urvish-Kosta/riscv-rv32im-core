# Provenance of docs/results/

Captured by `scripts/run_benchmarks.sh --csv docs/results/benchmarks.csv`
then `tools/perf_report.py` and `tools/plot_cpi.py`.

```
date        : 2026-07-24 22:44 UTC
simulator   : Verilator 5.050 2026-07-01 rev conda-forge build 0
compiler    : clang version 22.1.8 (https://github.com/conda-forge/clangdev-feedstock ea395ac6404d6e02629177af708e8855d6389063)
core commit : (set when committed)
```

Re-running the script regenerates every file here. Cycle counts are
deterministic for a given RTL + program, so the numbers reproduce exactly.
