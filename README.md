# riscv-rv32im-core

A from-scratch, 5-stage pipelined **RV32IM** RISC-V core in SystemVerilog,
verified in simulation against the Spike golden model, running real GCC-compiled
programs, with hardware performance counters and a Python instruction-trace
viewer for CPI/IPC analysis.

[![CI](https://github.com/Urvish-Kosta/riscv-rv32im-core/actions/workflows/ci.yml/badge.svg)](https://github.com/Urvish-Kosta/riscv-rv32im-core/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Status](https://img.shields.io/badge/status-M2%205--stage%20pipeline-yellow)

> **Scope (honest, verbatim):** *Designed and verified entirely in simulation
> (Verilator + Icarus). Not run on FPGA or silicon. All performance figures are
> cycle-accurate simulation results, reproducible via the included scripts.*

---

## Project status

**Current milestone: M2 — 5-stage pipeline (no hazard logic yet).** The
datapath is now pipelined into IF/ID/EX/MEM/WB (`rtl/core/core_pipe.sv`), with
branches/jumps resolved in EX. This milestone deliberately has **no forwarding,
stalls, or branch flush**, so it is correct only on hazard-free code; general
correctness arrives at M3. The single-cycle core (`rtl/core/core_top.sv`)
remains as the trusted **functional reference**.

The pipeline is verified **differentially against that reference**: hazard-free
directed programs plus randomized (seeded) programs all produce a bit-identical
result signature on both cores, one directed case also matches a hand-derived
signature, and an intentionally-hazardous case provably diverges (confirming the
core is genuinely un-forwarded). All M1 self-checking tests still pass.

There are **no measured performance results yet.** CPI/IPC, misprediction rates,
and stall breakdowns are produced only from committed, re-runnable scripts at
M5–M6, and this README will not state any such number before it has been measured.

| Milestone | What it delivers | State |
|---|---|---|
| **M0** | Repo skeleton, toolchain install/verify, Spike hello, Verilator smoke, CI | **done** |
| **M1** | Single-cycle RV32I (functional reference), self-checking directed tests | **done** |
| **M2** | Pipeline the datapath (no hazard logic yet) | **done** |
| M3 | Hazard detection + forwarding + control hazards; full RV32I `riscv-tests` | not started |
| M4 | RV32M mul/div (multi-cycle) + minimal Zicsr counters | not started |
| M5 | Branch prediction (bimodal → gshare) + perf counters + measured CPI | not started |
| M6 | Trace viewer + benchmark suite (Dhrystone) + CPI report | not started |
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
├── rtl/            core RTL (core/, mem/, include/riscv_pkg.sv)   # M2: single-cycle + pipeline
├── sim/            Verilator harness (verilator/) + committed waves (waves/)
├── sw/             test programs (common/ linker+crt, tests/, benchmarks/)
├── tools/          Python trace viewer / trace-compare / perf report / plot
├── tests/          riscv-tests hooks + self-check infra (wired at M3)
├── scripts/        build_toolchain.sh, run_tests.sh, run_benchmarks.sh
├── docs/           architecture, pipeline, hazards, prediction, counters, decisions
└── .github/        CI workflow
```

## Quick start

```sh
# 1. Install + verify the simulation toolchain (Ubuntu/Debian; macOS notes inside)
./scripts/build_toolchain.sh          # or: ./scripts/build_toolchain.sh --check

# 2a. Single-cycle core + RV32I self-checking suite
make -C sim/verilator                 # builds obj_dir/Vcore_top
make -C sw/tests run                  # assembles every test, runs it, reports pass/fail

# 2b. Pipeline (M2): differential check vs the single-cycle reference
make -C sim/verilator pipe            # builds obj_dir_pipe/Vcore_pipe
./scripts/run_pipe_diff.sh            # directed + randomized hazard-free programs

# (or) run the staged smoke script, which self-skips any missing tool
./scripts/run_tests.sh
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

The primary correctness argument is **lockstep trace-comparison against Spike**:
every program runs on both the RTL core and Spike, and retire traces are diffed
instruction-by-instruction — a divergence is a bug localized to the exact
instruction. `riscv-tests` provides per-instruction unit tests (CI subset), and
committed `.gtkw` waveforms provide visual evidence for each hazard class. The
M0 `hello` already exercises the HTIF `tohost` exit protocol these tests rely on.

**Current state (M1):** the single-cycle core is verified with self-checking
directed tests — an independent oracle, since expected values are derived from
the ISA rather than the core. Spike lockstep and the official `riscv-tests` are
the plan of record and land at **M3**, where a pipelined datapath genuinely
needs an instruction-by-instruction reference. Nothing here claims Spike results
that have not been produced.

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
