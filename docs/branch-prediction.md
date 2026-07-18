# Branch prediction

> **Status:** implemented at **M5** (`rtl/core/bpu.sv`), runtime-selectable.

## Design

Prediction happens at **IF** (direction alone is useless there without a
target, so a BTB is required):

- **BTB** — direct-mapped, 64 entries: `{valid, is_cond, tag, target}`. The tag
  is the *full* remaining PC (`pc[31:8]`), so **false hits are impossible** and
  a non-control instruction can never be predicted taken. This keeps
  misprediction strictly a performance event, never a correctness one.
- **Direction** — 256 × 2-bit saturating counters (PHT), reset weakly
  not-taken. Unconditional BTB entries (JAL/JALR) predict taken on hit.
- **Modes** (`cfg_bp_mode`, harness plusarg `+bp=`):
  `off` (always fall-through — bit-identical to the M3/M4 static-not-taken
  core), `bimodal` (PHT indexed by `pc[9:2]`), `gshare` (index `pc[9:2] XOR`
  8-bit global history register).

Resolution stays in EX. Every instruction carries its **predicted next PC**
down the pipe; EX computes the **actual next PC** for every instruction and
redirects iff they differ. This one comparison uniformly covers taken/not-taken
branches, JAL, JALR, and predictor-off operation (where `pred_npc` is always
`pc+4`, reducing exactly to the earlier design). Mispredict penalty: 2 cycles
(the existing flush path); correct predictions cost nothing.

The GHR updates non-speculatively at EX from resolved conditional branches
(decision #018 documents the trade-off vs. speculative history + repair).

## A real bug, found by measurement

The first gshare implementation *recomputed* the PHT index at update time from
the then-current GHR. Any branch resolving between predict and update shifts
the GHR, so training could hit a **different counter** than the one that
predicted — classic index inconsistency. The symptom was measured, not
guessed: gshare scored only ~25% mispredicts on a strictly alternating branch
it should memorize. The fix carries the predict-time index down the pipeline
and trains exactly that entry; the same benchmark then measures **0.3%**.
Both states are recorded below because the delta *is* the lesson.

## Measured results

Produced by `bash scripts/run_benchmarks.sh` (Verilator simulation; self-checking
benchmarks — a run counts only if architecturally correct). Numbers below are
from the run captured at M5 sign-off; re-run the script to reproduce.

| bench | mode | CPI | branch mispredicts |
|---|---|---|---|
| `bench_loop` (counted loop) | off | 1.666 | 99.9% (all taken) |
| | bimodal | **1.003** | 0.3% |
| | gshare | 1.008 | 1.1% |
| `bench_alt` (strict T/N alternation) | off | 1.666 | 75.0% |
| | bimodal | 1.445 | 50.1% (2-bit counters thrash) |
| | gshare | **1.003** | **0.3%** (history learns the pattern) |
| `bench_mixed` (loads + mul/div + nested loops) | off | 7.274 | 93.4% |
| | bimodal | 7.114 | 8.8% |
| | gshare | 7.133 | 19.0% |

Reading the table honestly: the loop and alternation kernels isolate the
predictors' textbook behaviours (bimodal ≈ perfect on loops, defeated by
alternation; gshare learns both). `bench_mixed` is dominated by the serial
~34-cycle MDU latency (8704 of ~10.3k cycles are MDU stalls), so prediction
barely moves its CPI — which is itself a truthful statement about where that
kernel's time goes (decision #016).
