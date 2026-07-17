# Verification

> **Status:** current as of milestone **M1** (single-cycle RV32I core).

## What is verified today (M1)

The single-cycle core is verified by **self-checking directed tests**: small
assembly programs, each of which computes results and compares them against
values **derived by hand from the ISA specification**. A mismatch stores a
non-zero exit code via the HTIF `tohost` protocol; a clean run stores `1`
(pass). Because the expected values come from the ISA and not from the core, the
tests are an **independent oracle** -- the core cannot "pass by agreeing with
itself".

Each test is assembled/linked (`sw/common/crt.S` + `sw/common/link.ld`),
converted to a memory image (`tools/bin2hex.py`), and run on the RTL under
Verilator (`sim/verilator`, `main.cpp` implements the `tohost` exit + an
optional per-cycle retire trace). Run the whole suite with:

```sh
make -C sim/verilator            # build the core simulator
make -C sw/tests run             # build + run every test, report pass/fail
```

### Coverage (`sw/tests/isa/`)

| Test | Exercises |
|---|---|
| `test_alu_imm`  | `ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI` (incl. signed/unsigned compare, arithmetic vs logical shift) |
| `test_alu_reg`  | `ADD SUB AND OR XOR SLL SRL SRA SLT SLTU` |
| `test_lui_auipc`| `LUI`, `AUIPC` (PC-relative checked via the difference of two `AUIPC`) |
| `test_branch`   | `BEQ BNE BLT BGE BLTU BGEU`, each taken **and** not-taken |
| `test_jal_jalr` | `JAL`/`JALR` control transfer **and** exact link-register value |
| `test_mem`      | `SW/LW`, `SB/LB/LBU`, `SH/LH/LHU`, byte/half lane masking, sign vs zero extension |
| `test_loop`     | backward branches + realistic accumulate/countdown loops |

All of the above currently pass. The core also executes the M0 `hello` program
(assembled from `sw/tests/hello/hello.S`) to a `tohost` PASS.

## The stronger argument, and why it is staged

The project's headline correctness method is **lockstep trace-comparison against
the Spike golden model**, backed by the official `riscv-tests`. That is the plan
of record and is scheduled at **M3**, when there is a pipelined datapath whose
behaviour genuinely needs an instruction-by-instruction reference (hazards,
forwarding, control-flow timing). The `tohost` mechanism the directed tests use
is deliberately the *same* protocol Spike and `riscv-tests` rely on, so wiring
them in is incremental rather than a rewrite.

Directed self-checking tests and Spike lockstep are complementary: the directed
tests give readable, intention-revealing per-instruction checks; Spike lockstep
gives broad, mechanical coverage over real compiled programs. M1 establishes the
former; M3 adds the latter.

## Honesty notes

- No result here comes from FPGA or silicon -- everything is Verilator simulation.
- No performance number (CPI/IPC, misprediction rate) is stated anywhere yet;
  those are produced only from committed scripts at M5-M6.
- Where a method is *planned* (Spike lockstep, `riscv-tests`), it is labelled as
  planned, not presented as already done.

---

## M2 — pipeline vs. single-cycle (differential)

The 5-stage pipeline (`core_pipe`) has no hazard logic yet, so it is verified on
**hazard-free** programs by differential comparison against the single-cycle
reference (`core_top`), which is itself verified against hand-derived ISA values
(above). Both cores run the same image and write a 32-bit result **signature**
to `tohost`; the signatures must match.

Run it with:

```sh
make -C sim/verilator both
bash scripts/run_pipe_diff.sh
```

What it checks (`sw/tests/pipe/`, `tools/gen_pipe_test.py`):

| Case | Purpose |
|---|---|
| `pipe_smoke` | small program; signature also matches a **hand-derived** `0x0000000a` (oracle independent of both cores) |
| `pipe_alu`   | broad ALU coverage; pipeline signature == reference |
| `pipe_ldst`  | loads/stores through MEM (byte/half/word, sign/zero ext); == reference |
| `rand_s1..s8`| randomized hazard-free programs (committed seeds); each == reference |
| `xfail_hazard_demo` | **intentionally hazardous**; MUST diverge from the reference, proving the pipeline is genuinely un-forwarded (reference `0xc`, pipeline `0x0`) |

All hazard-free cases match bit-for-bit; the hazardous case diverges as required.
The programs are branch-free and insert three NOPs after every real instruction,
which is the spacing a forwarding-free pipeline needs. M3 removes that constraint
(forwarding + stalls + flush) and folds these programs into the general suite.

---

## M3 — full hazard logic, verified on hazardous code

M3 adds forwarding, the load-use stall, and control flush; the pipeline is now
correct on arbitrary RV32I code. The differential methodology is unchanged but
the *programs* are now deliberately hazardous:

```sh
bash scripts/run_pipe_diff.sh   # builds both cores, runs everything below
```

| Evidence | What it shows |
|---|---|
| `hazard_demo` matches at hand-derived `0xc` | the exact program that **diverged** at M2 (`0x0` vs `0xc`) now agrees with the reference — before/after proof that forwarding works |
| randomized **hazardous** programs (`--hazard`, committed seeds 11–18) | dense back-to-back RAW chains, immediate load-use consumption, stores of just-computed values: signatures bit-identical to the reference |
| full M1 ISA suite **on the pipeline** (`make -C sw/tests run SIM=.../Vcore_pipe`) | every self-checking test (saturated with hazards and taken/not-taken branches) passes with the ISA-derived expected values |
| M2 hazard-free set + seeds still pass | no regression on the easy cases |

The hazardous generator (`tools/gen_pipe_test.py --hazard`) biases sources
toward recent destinations (RAW chains), emits loads that are consumed on the
very next instruction (load-use stall), and stores just-computed registers
(store-data forwarding). Seeds are committed, so every run is reproducible.

Spike lockstep + the official `riscv-tests` remain the documented plan of
record; they were not runnable in the build environment used here (no Spike),
and nothing above claims otherwise. The differential chain used instead is:
ISA-derived values → single-cycle core → pipeline, with the ISA suite also run
directly on the pipeline.

---

## M4 — RV32M + counter CSRs

Three layers of evidence, from unit to system:

1. **MDU unit testbench** (`sim/verilator/tb_mdu.sv`, `make -C sim/verilator
   mdu_tb`): the iterative multiply/divide RTL is compared against
   `riscv_pkg::mdu_func` — the behavioural encoding of the RV32M spec — on all
   8 ops × 64 edge-operand pairs (0, ±1, `0x80000000`, `0x7FFFFFFF`, …,
   including every divide-by-zero and the `MIN_INT / -1` overflow) plus 500
   seeded random vectors: **1012/1012**.
2. **Differential, hazardous, with M ops**: the random generator now mixes
   `mul/mulh*/div*/rem*` into its hazardous programs, so multi-cycle EX stalls
   interact with RAW chains, load-use stalls, and stores. Pipeline signatures
   remain bit-identical to the reference — which computes M results
   *behaviourally* via the same `mdu_func`, so this simultaneously proves the
   iterative RTL against the executable spec at system level.
3. **Directed self-checking** (`test_mul`, `test_div`, `test_csr`): hand-derived
   values for every M edge case, run on *both* cores; CSR monotonicity and
   sanity checks.

### A test bug worth recording

The first `test_csr` asserted that two *adjacent* `rdinstret` reads always
differ. The pipeline correctly refuses to count flush bubbles in `instret` —
and in this test two bubbles from a taken branch were retiring exactly between
the two reads, so both reads returned the same (correct) value. The single-cycle
core, having no bubbles, masked the bad assumption. The fix places real
instructions between the reads. Lesson kept here deliberately: implementation-
dependent timing must not leak into architectural assertions.
