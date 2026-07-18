# Performance counters

> **Status:** implemented at **M5** (pipeline core only).

## Counters

Standard (Zicsr, read-only, both cores): `cycle`/`cycleh` (0xC00/0xC80),
`instret`/`instreth` (0xC02/0xC82). The pipeline's `instret` counts only valid
retires — flush/stall bubbles are excluded.

Non-standard (custom read-only CSR space, pipeline only; the reference core
reads them as 0 by design):

| CSR | Name | Counts |
|---|---|---|
| 0xFC0 | `perf_loaduse`  | cycles lost to load-use stalls |
| 0xFC1 | `perf_mdu`      | cycles lost to multi-cycle mul/div stalls |
| 0xFC2 | `perf_redirect` | control redirects (each costs 2 flush cycles) |
| 0xFC3 | `perf_br`       | conditional branches resolved |
| 0xFC4 | `perf_br_tk`    | conditional branches taken |
| 0xFC5 | `perf_br_mp`    | conditional branches that redirected (mispredicts) |

Software reads them with `csrrs rd, 0xFCx, x0`; `sw/tests/pipeonly/
test_perfcsr.S` checks they move when the corresponding events occur. The
simulation harness mirrors them (`dbg_n_*`) and prints a `[perf]` line at halt
with cycles, retired instructions, CPI, and all six counters — every number
observed in that run.

## Measuring

```sh
bash scripts/run_benchmarks.sh     # all benchmarks x {off, bimodal, gshare}
```

The CPI accounting closes: for example `bench_loop` with prediction off retires
3009 instructions in 5012 cycles; the extra ~2000 cycles are exactly
2 × 1000 taken-branch redirects (+ startup), and with bimodal prediction the
same program runs at CPI 1.003. `bench_mixed`'s 8704 MDU-stall cycles equal
256 M-ops × 34 cycles exactly. Where the numbers can be cross-checked
arithmetically, they do check out — that closure is the point of the counters.

Per the project's honesty rule, no performance figure appears anywhere in this
repository unless it was produced by a committed script that anyone can re-run;
the tables in `docs/branch-prediction.md` state the capture context.
