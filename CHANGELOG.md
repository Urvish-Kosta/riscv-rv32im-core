# Changelog

All notable changes to this project. Milestones (M0–M7) are the development
sequence described in the README; each was completed and verified before the
next began.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] — M7: documentation, diagrams, polish

### Added
- Architecture documentation with module-hierarchy and datapath diagrams.
- Committed waveform (`sim/waves/hazard_showcase.vcd`) plus GTKWave save file
  and `scripts/make_waves.sh` to regenerate it; the showcase program exercises
  every hazard class in 59 cycles.
- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, this changelog.

### Changed
- README rewritten around measured results and the actual verification chain.

### Fixed
- **Waveform dumping fired on every traced run.** Verilator matches plusargs by
  prefix, so the VCD flag `+trace` also matched `+trace_file=...`; every
  lockstep run dumped a full waveform (269 MB on the benchmark suite). The
  flags are now distinct (`+vcd`) and matching is exact.
- **`.gitignore` missed `obj_dir_pipe/` and `obj_dir_mdu/`** — the pattern was
  `obj_dir/`, so 44 generated files would have been committed. Now `obj_dir*/`,
  with an explicit exception keeping the committed waveform.
- **Stale claims removed.** The README previously stated verification "against
  the Spike golden model" (Spike was never run in this environment) and, in a
  later paragraph, that no performance results existed (they did, from M5).
  Both are corrected; the reference model is now named accurately throughout.
- Removed an empty `tests/` directory whose description promised
  `riscv-tests` infrastructure that was never wired up; the real tests live in
  `sw/tests/`.

## [0.6.0] — M6: tracing, benchmarks, reports

### Added
- Retire-trace output from both cores (`+trace_file=`), with a retire-aligned
  store view and a defined trace end point so traces are directly comparable.
- `tools/trace_compare.py` — lockstep comparison localizing the first
  divergence, with timing-CSR taint classification and a `--strict` mode.
- `tools/trace_viewer.py` — annotated listing; cycle gaps show stall costs.
- `tools/rvdisasm.py`, `tools/perf_report.py`, `tools/plot_cpi.py`.
- Five self-checking C benchmark kernels + C runtime (`crt0.S`, `bench.h`),
  with golden values derived independently on the host.
- `scripts/run_lockstep.sh`; committed measured results in `docs/results/`.

### Fixed
- Store records were attached to the wrong instruction in pipeline traces
  (EX/MEM write port vs. MEM/WB retire record).
- Traces ended at different points on the two cores; now both end when the
  halting store retires, with counters snapshotted at the halt cycle.

### Notes
- Dhrystone deliberately **not** included or approximated; no DMIPS quoted.
  Rationale and integration instructions in `docs/benchmarks.md`.

## [0.5.0] — M5: branch prediction and measured performance

### Added
- `rtl/core/bpu.sv`: full-tag 64-entry BTB + 256×2-bit PHT; `off`/`bimodal`/
  `gshare` selectable at runtime.
- Uniform mispredict detection (actual next-PC vs. predicted next-PC in EX).
- Six performance counters exposed as read-only CSRs; harness CPI report.
- `scripts/run_benchmarks.sh` and the first measured CPI figures.

### Fixed
- gshare trained the wrong PHT entry because the index was recomputed at update
  time from a GHR that had since shifted. The predict-time index is now carried
  down the pipeline. Measured mispredict rate on an alternating branch went
  from ~25% to 0.3%.

## [0.4.0] — M4: RV32M and counter CSRs

### Added
- `riscv_pkg::mdu_func`: behavioural RV32M semantics used by the reference core.
- `rtl/core/mdu.sv`: iterative ~34-cycle multiply/divide stalling in EX.
- `sim/verilator/tb_mdu.sv`: 1012-case unit testbench against the spec function.
- Minimal Zicsr: read-only `cycle`/`instret` (+h); `instret` excludes bubbles.

### Fixed
- Multiplier dropped the high-word carry; divider needed a 33-bit partial
  remainder.
- A project test asserted that two adjacent `rdinstret` reads always differ —
  an implementation-dependent assumption the pipeline correctly refused to
  satisfy (flush bubbles are not counted). Test corrected.

## [0.3.0] — M3: hazard handling

### Added
- Forwarding (EX/MEM and MEM/WB → EX), WB→ID bypass, single-bubble load-use
  stall, control flush on taken branches and jumps.
- Hazardous mode for the randomized program generator.

## [0.2.0] — M2: 5-stage pipeline

### Added
- `rtl/core/core_pipe.sv` with no hazard logic (by design), verified
  differentially on hazard-free programs — and *proven* un-forwarded by a
  hazardous program that diverges from the reference.
- DUT-generic harness building both cores.

## [0.1.0] — M1: single-cycle reference

### Added
- Single-cycle RV32I core (`core_top.sv`) and Harvard memories.
- Self-checking directed ISA tests with hand-derived expected values.

### Fixed
- Decode fields were written as one-time initializers rather than continuous
  assignments, freezing every decoded field at its reset value.

## [0.0.1] — M0: scaffolding

### Added
- Repository skeleton, toolchain scripts, Verilator smoke test, CI, MIT license,
  documentation stubs, and the honest-scope statement.
