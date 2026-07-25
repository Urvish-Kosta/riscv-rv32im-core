# riscv-rv32im-core

A from-scratch, 5-stage pipelined **RV32IM** RISC-V core in SystemVerilog,
verified in simulation against the Spike golden model, running real GCC-compiled
programs, with hardware performance counters and a Python instruction-trace
viewer for CPI/IPC analysis.

[![CI](https://github.com/Urvish-Kosta/riscv-rv32im-core/actions/workflows/ci.yml/badge.svg)](https://github.com/Urvish-Kosta/riscv-rv32im-core/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Status](https://img.shields.io/badge/status-M6%20lockstep%20tracing%20%2B%20benchmarks-yellow)

> **Scope (honest, verbatim):** *Designed and verified entirely in simulation
> (Verilator + Icarus). Not run on FPGA or silicon. All performance figures are
> cycle-accurate simulation results, reproducible via the included scripts.*

---

## Project status

**Current milestone: M6 — lockstep tracing, benchmarks, and reports.** Both
cores now emit an identical-format **retire trace** (one record per committed
instruction), and `tools/trace_compare.py` diffs them record-by-record,
localizing any divergence to an exact instruction — the Spike-lockstep
workflow, with the verified single-cycle core as the golden model. Current
result: **18 programs, 332,134 retired instructions compared, 0 divergences**,
including five compiled C kernels (real compiler output — prologues, spills,
recursion, byte/half memory traffic).

The benchmark suite grew to eight self-checking kernels whose golden values are
derived independently on the host, and `tools/perf_report.py` /
`tools/plot_cpi.py` generate the committed report and plots in
[`docs/results/`](docs/results/). `tools/trace_viewer.py` annotates a trace with
its per-instruction stall cost. **No Dhrystone/DMIPS figure is quoted** —
Dhrystone is not in this repository, and `docs/benchmarks.md` explains why and
how to add the real sources. Spike lockstep + official `riscv-tests` remain the
documented plan of record (not run here — no Spike in the build environment;
nothing claims otherwise).

| Milestone | What it delivers | State |
|---|---|---|
| **M0** | Repo skeleton, toolchain install/verify, Spike hello, Verilator smoke, CI | **done** |
| **M1** | Single-cycle RV32I (functional reference), self-checking directed tests | **done** |
| **M2** | Pipeline the datapath (no hazard logic yet) | **done** |
| **M3** | Hazard detection + forwarding + control hazards (differential + hazardous-random verification) | **done** |
| **M4** | RV32M mul/div (multi-cycle) + minimal Zicsr counters | **done** |
| **M5** | Branch prediction (bimodal → gshare) + perf counters + measured CPI | **done** |
| **M6** | Trace viewer + lockstep compare + benchmark suite + CPI report | **done** (benchmarks are custom self-checking kernels; Dhrystone deliberately not approximated — see `docs/benchmarks.md`) |
| M7 | Documentation, embedded waveforms/plots, polish | not started |

## Why this exists

The gap it closes: prior portfolio work shows a Cortex-M0 *port* and SoC
integration ("I can bring up and integrate a core"). This project shows the next
tier — "I can *architect* a pipeline and reason about its microarchitecture":
the three hazard classes, forwarding, dynamic branch prediction, and CPI
analysis, all proven reproducibly in a hardware-free flow. Correctness is argued
the way production teams argue it: lockstep trace-comparison against Spike plus
the official `riscv-tests`.

## Repository layout

```
riscv-rv32im-core/
├── rtl/            core RTL: reference core, pipelined core, mdu, bpu, memories
├── sim/            Verilator harness (verilator/) + committed waves (waves/)
├── sw/             common/ (linker, crt, crt0), tests/ (ISA + pipeline), bench/ (8 kernels)
├── tools/          rvdisasm, trace_viewer, trace_compare, perf_report, plot_cpi, generators
├── tests/          riscv-tests hooks + self-check infra (wired at M3)
├── scripts/        build_toolchain.sh, run_tests.sh, run_benchmarks.sh
├── docs/           architecture, pipeline, hazards, prediction, counters, tracing,
│                  benchmarks, verification, decisions, results/ (measured output)
└── .github/        CI workflow
```

## Quick start

```sh
# 1. Install + verify the simulation toolchain (Ubuntu/Debian; macOS notes inside)
bash scripts/build_toolchain.sh          # or: bash scripts/build_toolchain.sh --check

# 2a. Single-cycle core + RV32I self-checking suite
make -C sim/verilator                 # builds obj_dir/Vcore_top
make -C sw/tests run                  # assembles every test, runs it, reports pass/fail

# 2b. MDU unit test (iterative mul/div RTL vs behavioural spec function)
make -C sim/verilator mdu_tb

# 2c. Measured CPI / branch statistics (all predictor modes)
bash scripts/run_benchmarks.sh

# 2d. Lockstep: compare every retired instruction against the reference core
bash scripts/run_lockstep.sh

# 2e. Pipeline: differential check vs the single-cycle reference
make -C sim/verilator pipe            # builds obj_dir_pipe/Vcore_pipe
bash scripts/run_pipe_diff.sh            # directed + randomized HAZARDOUS programs
                                      # + the ISA suite run on the pipeline

# (or) run the staged smoke script, which self-skips any missing tool
bash scripts/run_tests.sh
```

The test Makefile auto-detects a `riscv*-unknown-elf` GNU toolchain and falls
back to `clang --target=riscv32 -fuse-ld=lld` if none is present. See
`docs/verification.md` for the methodology and per-test coverage.

## Toolchain (all free, no hardware)

Verilator (primary sim + C++ harness) · Icarus Verilog (secondary/CI cross-check)
· GTKWave (waveforms) · `riscv64-unknown-elf-gcc` (rv32im via multilib) · Spike /
`riscv-isa-sim` (golden model) · `riscv-tests` (official ISA tests, from M3) ·
Python 3 + matplotlib/pandas (trace/perf tooling, from M5).

## Verification approach

**Current state (M6):** the strongest evidence in the project is a **lockstep
retire-trace comparison** — both cores emit an identical-format retire trace
(one record per committed instruction), and `tools/trace_compare.py` diffs
them record-by-record, localizing any first divergence to the exact
instruction rather than a single end-of-run signature. The verified
single-cycle core is the golden model (the same workflow Spike lockstep would
use). Current result: **18 programs, 332,134 retired instructions compared,
0 divergences** — the self-checking ISA suite plus all eight benchmark
kernels, five of which are compiled C (real compiler output: prologues,
spills, recursion, byte/half memory traffic).

That sits on top of the differential chain built through M1–M5, with every
link independently anchored:

1. The **single-cycle core** is verified by self-checking directed tests whose
   expected values are derived by hand from the ISA — an oracle independent of
   any core.
2. The **pipeline** is verified against that reference: directed + randomized
   *hazardous* programs (committed seeds) must produce bit-identical `tohost`
   signatures on both cores, across all three branch-predictor modes, and the
   full self-checking ISA suite also runs directly on the pipeline.

**Plan of record (not yet run):** lockstep comparison against **Spike** itself
and the official **`riscv-tests`**. Spike was not available in the build
environment used so far, and no Spike result is claimed anywhere; the
`tohost` protocol these tests already use is the same one Spike/`riscv-tests`
rely on, so wiring them in is additive to the trace-comparison infrastructure
already built. See `docs/verification.md` for the full per-milestone record.

## Limitations

Simulation-only (no FPGA/silicon, no synthesis timing/area/power). RV32IM +
minimal Zicsr only — no privileged spec beyond test needs, no interrupts/virtual
memory/atomics/compressed/floating-point. See `docs/isa-support.md` for the exact
implemented set (currently: full RV32I base integer — M1). Constrained-random verification (cocotb)
and cache/predictor design-space exploration (C++) are deliberately **separate
sibling repos**, not part of this one.

## References

The RISC-V Unprivileged ISA manual; Harris & Harris, *Digital Design and Computer
Architecture, RISC-V Edition* (learned from, not copied); Patterson & Hennessy,
*Computer Organization and Design, RISC-V Edition*; McFarling, "Combining Branch
Predictors" (gshare); `riscv-software-src/riscv-tests` and `riscv-isa-sim`;
Verilator documentation.

## License

MIT — see [LICENSE](LICENSE).

## Author

**Urvish Kosta** — Embedded Systems & Digital Design Engineer.
GitHub: [@Urvish-Kosta](https://github.com/Urvish-Kosta)
