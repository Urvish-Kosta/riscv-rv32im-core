# Provenance of `docs/results/`

Every file in this directory is generated. Regenerate all of it with:

```sh
bash scripts/run_benchmarks.sh --csv docs/results/benchmarks.csv
python3 tools/perf_report.py docs/results/benchmarks.csv -o docs/results/performance.md
python3 tools/plot_cpi.py   docs/results/benchmarks.csv --outdir docs/results
```

| file | contents |
|---|---|
| `benchmarks.csv` | raw measured counters: cycles, retires, stalls, redirects, branch statistics |
| `performance.md` | generated report: CPI, speedups, mispredict rates, cycle accounting |
| `cpi.png` | measured CPI per benchmark per predictor mode |
| `mispredict.png` | measured conditional-branch mispredict rate |

## Capture environment

```
captured  : 2026-07-30 20:03 UTC
simulator : Verilator 5.050 2026-07-01 rev conda-forge build 0
compiler  : clang version 22.1.8 (https://github.com/conda-forge/clangdev-feedstock ea395ac6404d6e02629177af708e8855d6389063)
```

Cycle counts are deterministic for a given RTL revision and program, so
a re-run on any machine reproduces these numbers exactly. The figures were
reproduced bit-identically on a freshly rebuilt toolchain during M7.
