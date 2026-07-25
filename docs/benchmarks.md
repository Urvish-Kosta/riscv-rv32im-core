# Benchmarks

> **Status:** current as of milestone **M6**.

## What is here

Eight kernels in `sw/bench/`, all **self-checking** — each computes a result
and compares it against a golden value, so a performance figure is only ever
reported for a run that was architecturally correct.

| kernel | language | what it stresses |
|---|---|---|
| `bench_loop`   | asm | tight counted loop — the taken-branch penalty |
| `bench_alt`    | asm | strictly alternating branch — defeats bimodal, learnable by gshare |
| `bench_mixed`  | asm | nested loops with loads/stores and mul/div together |
| `bench_crc32`  | C | bit manipulation, byte loads, no multiply |
| `bench_sieve`  | C | byte memory traffic, data-dependent branches, one multiply per prime |
| `bench_matmul` | C | 16×16 integer matrix multiply — multiply-bound |
| `bench_sort`   | C | insertion sort — data-dependent inner-loop branches |
| `bench_fib`    | C | naive recursion — call/return (JALR) and stack traffic |

The C kernels build freestanding (no libc) against `sw/common/crt0.S`
(stack setup, `.bss` zeroing, `main()`'s return value reported over HTIF) and
`sw/common/bench.h` (the handful of helpers they need).

## Where the golden values come from

Each C kernel was mirrored in Python **on the host** and its result computed
there; those constants live in `sw/bench/expected.h`. The oracle is therefore
independent of the core — the same principle used for the ISA tests at M1.
The derivation script is embedded in the commit that introduced the header and
is reproducible: the PRNG, the CRC polynomial, and the checksum folds are all
specified exactly in the C source.

## Running

```sh
bash scripts/run_benchmarks.sh                              # table on stdout
bash scripts/run_benchmarks.sh --csv docs/results/benchmarks.csv
python3 tools/perf_report.py docs/results/benchmarks.csv -o docs/results/performance.md
python3 tools/plot_cpi.py   docs/results/benchmarks.csv --outdir docs/results
```

Committed output lives in `docs/results/` (CSV, generated report, and the two
plots), with capture provenance in `docs/results/README.md`. Cycle counts are
deterministic for a given RTL and program, so re-running reproduces them
exactly.

## On Dhrystone — not included, and why

The project plan named Dhrystone as the headline benchmark. **It is not in this
repository, and no DMIPS figure is quoted anywhere.**

Dhrystone is a specific published program; a from-memory reimplementation would
not be Dhrystone, and any "DMIPS" derived from it would be a fabricated number
dressed up as a standard one. It also depends on C string/library routines that
this bare-metal environment does not provide. Rather than approximate it and
report a familiar-sounding score, the suite above uses kernels whose behaviour
is fully specified in this repository and whose results are independently
checked.

Adding the real thing later is straightforward and deliberately unblocked: drop
the official `dhry_1.c` / `dhry_2.c` / `dhry.h` into `sw/bench/dhrystone/`,
provide the few libc routines it calls (`strcpy`, `strcmp`, `memcpy` — the
`bench.h` helpers are most of it), and it will be picked up by
`run_benchmarks.sh` like any other kernel. Until that source is actually
present and running, no Dhrystone number appears here.

## Reading the results honestly

- `bench_matmul` and `bench_mixed` sit near CPI 7 because they are dominated by
  the **iterative** multiply/divide unit (~34 cycles each, decision #016): in
  `bench_matmul`, 4096 multiplies × 34 = 139,264 stall cycles — 85.6% of the
  run. Branch prediction barely moves those kernels, and the report says so.
- `bench_fib` is the one case where **bimodal mispredicts more often than no
  prediction at all** (50.0% vs 38.2%) yet still runs faster: with prediction
  off every taken branch costs 2 cycles, whereas the BTB also predicts the
  function returns, so total cycles fall even as the conditional-branch
  mispredict rate rises. The two metrics measure different things; both are
  reported rather than picking the flattering one.
- The cycle accounting closes: for every benchmark,
  `cycles − retired − load-use − MDU − 2×redirects` leaves exactly **1** cycle
  (reset). Counters that add up are counters worth trusting.
