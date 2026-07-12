# Pipeline (stage-by-stage)

> **Status:** current as of milestone **M2** (5-stage pipeline, no hazard logic).

The pipelined core (`rtl/core/core_pipe.sv`) splits the single-cycle datapath
into five stages separated by pipeline registers. It reuses the same leaf
modules as the single-cycle reference (`regfile`, `alu`, `imm_gen`, `control`,
`imem`, `dmem`); only the staging and control-transfer logic are new.

```
IF ──▶ IF/ID ──▶ ID ──▶ ID/EX ──▶ EX ──▶ EX/MEM ──▶ MEM ──▶ MEM/WB ──▶ WB
```

## Stages

- **IF** — PC register; instruction fetch from `imem`; computes `pc+4`. Next PC
  is `pc+4` unless the EX stage asserts a redirect (taken branch / jump).
- **ID** — decode (`control`), register-file read, immediate generation
  (`imm_gen`). Produces all control signals for the instruction.
- **EX** — ALU operation; branch condition + branch/jump target; drives the PC
  redirect back to IF.
- **MEM** — data-memory access (`dmem`); load sign/zero extension; selects the
  writeback value (ALU result / load data / `pc+4`).
- **WB** — writes the result back to the register file.

## Pipeline-register contents

| Register | Carries |
|---|---|
| IF/ID  | `pc`, `instr` |
| ID/EX  | control bits, `pc`, `rs1`/`rs2` values, `imm`, `rd`, `funct3` |
| EX/MEM | control bits, ALU result, store data (`rs2`), `pc+4`, `rd`, `funct3` |
| MEM/WB | `reg_write`, `rd`, final writeback value |

(Each register also carries `pc`/`instr` for the retire trace; those bits are
debug-only and would be stripped for synthesis.)

## What is intentionally missing at M2

This milestone builds the **structure** of the pipeline with **no hazard
handling**:

- **No data forwarding.** A dependent instruction reads its operands in ID while
  the producer may still be in EX/MEM/WB. Without forwarding it must be at least
  three instructions after its producer (two independent instructions or NOPs in
  between).
- **No stalls.** Nothing detects a load-use hazard and inserts a bubble.
- **No branch flush.** Branches/jumps resolve in EX and redirect the PC, but the
  two instructions already fetched behind them are **not** squashed — a taken
  control transfer therefore has two architectural delay slots.

As a result the M2 core is correct only on **hazard-free code**. This is proven,
not assumed: see `docs/verification.md`. The intentionally-hazardous
`xfail_hazard_demo` diverges from the single-cycle reference (reference `0xc`,
pipeline `0x0`), which is exactly the un-forwarded behaviour expected here.

## What M3 adds

Forwarding (EX/MEM and MEM/WB → EX), a load-use stall, and branch flush, so the
core becomes correct on arbitrary code and the delay slots and NOP-padding
disappear. The single-cycle core remains the reference throughout.
