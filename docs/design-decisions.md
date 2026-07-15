# Design Decisions Log

The "why" behind the microarchitecture — the record I use to defend every choice
in an interview. Each entry: the decision, the alternatives considered, and the
trade-off. New entries are appended as decisions are actually made; nothing here
describes RTL that does not yet exist.

Format: `#NNN — <decision>` · **Status** (Decided / Revisit) · **Milestone**.

---

### #001 — Simulation-only flow (no FPGA/silicon) · Decided · M0
**Choice:** Verify entirely in simulation (Verilator primary, Icarus secondary),
with Spike as the golden model. No synthesis, timing, area, or power claims.
**Why:** No hardware access currently. A rigorous simulation flow (lockstep
golden-model co-simulation) is a stronger and more honest signal than an
unverified board photo. **Trade-off:** cannot claim fmax/utilization; an optional
Yosys gate-count estimate is allowed later *only if actually run*.

### #002 — Base ISA RV32I, plus M and minimal Zicsr · Decided · M0
**Choice:** RV32I first; add RV32M (mul/div) at M4; minimal Zicsr for `mcycle`/
`minstret`. **Why:** RV32I is fully specified and runs real GCC-compiled C; M
lets real benchmarks run; putting the counters in *standard* CSRs (Zicsr) avoids
bolted-on hacks. **Trade-off:** more decode/CSR work than a bare RV32I, but the
performance story (M5) depends on it.

### #003 — Five-stage pipeline (IF/ID/EX/MEM/WB) · Decided · M0
**Choice:** The classic 5-stage RISC pipeline. **Why:** canonical teaching and
interview target; every hazard/forwarding case has a well-understood answer I can
explain on a whiteboard. **Alternatives:** deeper pipeline (more hazard/forwarding
complexity, higher mispredict penalty) or single-cycle only (no pipeline story).
**Trade-off:** 5 stages is the sweet spot for demonstrating hazard reasoning
without incidental complexity.

### #004 — Resolve branches in EX (baseline) · Decided (Revisit at M5) · M0
**Choice:** Branch condition/target computed in EX; 2-cycle mispredict penalty.
**Why:** simplest correct choice to start. **Trade-off:** ID-stage resolution
would cut the penalty but adds comparators/forwarding into ID; I will document
that alternative and its cost, and revisit when adding dynamic prediction (M5).

### #005 — Write-first register file · Decided · M0
**Choice:** Regfile writes in the first half of the cycle, reads in the second.
**Why:** removes the WB→ID forwarding case entirely (a standard technique).
**Trade-off:** relies on a within-cycle write-before-read assumption that is fine
in simulation and standard in this teaching pipeline; I note it explicitly so it
is a conscious assumption, not an accident.

### #006 — Harvard, single-cycle memory model (initially) · Decided · M0
**Choice:** Split instruction/data memories, single-cycle, no cache. **Why:**
isolates pipeline behaviour from memory-latency effects so hazard analysis is
clean. **Trade-off:** unrealistic latency; memory/cache latency modelling is
deliberately a *sibling repo* (the C++ performance simulator), not this one.

### #007 — Multi-cycle iterative mul/div (stalls EX) · Decided · M4-scoped · M0
**Choice:** Iterative multi-cycle mul/div unit that stalls EX until it retires.
**Why:** honest about the real area/latency trade-off; a single-cycle 32×32
multiplier would misrepresent hardware cost. **Trade-off:** introduces a
deliberate structural hazard on EX — documented, not hidden.

### #008 — SystemVerilog as the HDL · Decided · M0
**Choice:** SystemVerilog. **Why:** matches prior industry RTL experience and is
the industry norm; fully simulable with free tools (Verilator/Icarus).
**Trade-off:** none material for this project; VHDL would also work but SV is the
better portfolio signal here.

### #009 — Testbench owns the `tohost` magic address, not the RTL · Decided · M1
**Choice:** the core exposes its data-memory write port and retiring-instruction
fields as `dbg_*` outputs; the Verilator harness (`main.cpp`) watches them and
implements the HTIF `tohost` exit protocol. **Why:** keeps the magic exit
address out of synthesizable RTL — the datapath has no special-cased address —
while still giving the simulator a clean stop condition and a per-cycle retire
trace. **Trade-off:** a few debug-only ports on the top module; they carry no
functional logic and would be stripped for synthesis.

### #010 — M1 verified by self-checking directed tests (independent oracle) · Decided · M1
**Choice:** verify the single-cycle core with hand-written assembly tests whose
expected values are derived from the ISA spec, signalling pass/fail over
`tohost`. **Why:** it is a genuine independent oracle (the core cannot pass by
agreeing with itself) and it is readable — each test states intent per
instruction. It also does not depend on a Spike build being present in the
environment. **Trade-off:** narrower mechanical coverage than lockstep
trace-comparison over large compiled programs; that stronger method
(Spike + `riscv-tests`) is the plan of record at **M3**, using the same `tohost`
protocol these tests already exercise, so it is additive rather than a rewrite.

### #011 — Branches/jumps resolved in EX; no flush at M2 · Decided · M2
**Choice:** the pipeline resolves control transfers in EX and redirects the PC,
but does **not** squash the two younger instructions already in IF/ID at M2.
**Why:** it isolates the datapath-staging work (M2) from control-hazard handling
(M3); the redirect path is correct, only the flush is deferred. **Trade-off:**
two architectural delay slots at M2, so M2 code must be hazard-free; M3 adds the
flush and the delay slots disappear.

### #012 — Verify the pipeline differentially against the single-cycle core · Decided · M2
**Choice:** check `core_pipe` by running hazard-free programs on both it and the
verified single-cycle `core_top` and comparing a `tohost` result signature,
including randomized seeded programs and one hand-derived anchor. **Why:** the
single-cycle core is already an independent-oracle-tested reference, so a
bit-for-bit signature match is strong evidence of datapath correctness without
needing Spike in this environment. An intentionally-hazardous case asserts the
*absence* of forwarding, so the test is meaningful and not vacuously passing.
**Trade-off:** covers only hazard-free code at M2 — exactly this milestone's
scope; Spike lockstep over arbitrary programs remains the M3 plan of record.

### #013 — WB→ID bypass instead of a write-first regfile · Decided · M3
**Choice:** keep the shared regfile sync-write/comb-read and add an explicit
WB→ID bypass in the pipeline for the distance-3 case. **Why:** making the
regfile itself write-first would forward the single-cycle core's writeback into
its own same-cycle operand read — a combinational loop through ALU/load logic.
An explicit bypass keeps both cores on one regfile and makes the hazard visible
in the pipeline code where it belongs. **Trade-off:** two extra muxes in ID.

### #014 — Classic single-bubble load-use stall (no MEM→EX load forwarding) · Decided · M3
**Choice:** EX/MEM forwards only values already computed (ALU result, `pc+4`),
never load data; a load-use pair stalls exactly one cycle and the value arrives
via MEM/WB. **Why:** forwarding dmem's combinational read output straight into
EX would chain memory-read + ALU into one cycle — the classic critical-path
mistake; the single-bubble design is the standard answer and is what the
interview question expects you to defend. **Trade-off:** 1-cycle penalty on
load-use pairs, measured honestly by the perf counters at M5.
