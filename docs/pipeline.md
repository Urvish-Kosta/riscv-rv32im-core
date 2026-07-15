# Pipeline (stage-by-stage)

> **Status:** current as of milestone **M3** (full hazard handling).

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

## Hazard handling (M3)

The core is correct on **arbitrary RV32I code** — no NOP padding, no delay
slots. Four mechanisms cooperate:

- **Forwarding into EX.** Operand muxes ahead of the ALU select, per source
  register (priority: youngest first):
  1. **EX/MEM** — the instruction one ahead, *if* its value already exists in
     MEM (ALU result or `pc+4`; never load data, `exmem_wb_sel != WB_MEM`);
  2. **MEM/WB** — the instruction two ahead (final writeback value: covers ALU
     results, `pc+4`, and load data alike);
  3. otherwise the ID/EX register value.
  The forwarded operands feed the ALU, the branch comparator, the JALR target,
  and the store data captured into EX/MEM.
- **WB → ID bypass.** The register file is sync-write/comb-read, so a value
  retiring this cycle is bypassed to a reader in ID. (The regfile itself is not
  write-first: in the single-cycle core that would form a combinational loop
  through its own writeback path — decision #013.)
- **Load-use stall.** A load in EX whose `rd` matches a source of the
  instruction in ID: PC and IF/ID hold for one cycle and a bubble enters EX.
  One cycle later the consumer is in EX with the load in WB, and MEM/WB
  forwarding supplies the value — the classic single-bubble load-use penalty.
- **Control flush.** A redirect from EX (taken branch, `JAL`, `JALR`) squashes
  the two younger wrong-path instructions (IF/ID and ID/EX become bubbles).
  Taken-branch penalty: 2 cycles. Not-taken branches cost nothing. (Reducing
  the taken penalty is the branch-prediction work at M5.)

Stall and redirect cannot coincide (the stall condition requires a *load* in
EX, and a load never redirects), which keeps the priority logic trivial.

## History: the M2 no-hazard baseline

M2 built this same 5-stage structure with hazard handling deliberately absent,
and *proved* the absence: `hazard_demo` (dense back-to-back RAW chains) diverged
from the single-cycle reference — reference `0xc`, un-forwarded pipeline `0x0`.
At M3 the same program matches at `0xc` on both cores. See
`docs/verification.md` for the full evidence chain.
