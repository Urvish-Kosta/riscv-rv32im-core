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
