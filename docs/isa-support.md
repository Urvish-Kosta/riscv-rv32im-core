# ISA Support

This file states **exactly** what is implemented in the RTL at any given time.
It is the single source of truth for scope honesty — no claim of full-ISA or
privileged-spec support is made anywhere in this repo beyond what this table shows.

**As of milestone M4: RV32IM is implemented in both cores** — the single-cycle
reference (behavioural one-cycle M results) and the 5-stage pipeline (iterative
multi-cycle M unit) — plus a minimal read-only slice of Zicsr (counter CSRs).
Verified as described in `docs/verification.md`. A group is marked *implemented*
only once it is built and passes its tests.

## Base integer — RV32I

| Group | Instructions | Status | Landed at |
|---|---|---|---|
| Integer register-register | `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND` | **implemented** | M1 |
| Integer register-immediate | `ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI` | **implemented** | M1 |
| Upper immediate | `LUI AUIPC` | **implemented** | M1 |
| Loads | `LB LH LW LBU LHU` | **implemented** | M1 |
| Stores | `SB SH SW` | **implemented** | M1 |
| Branches | `BEQ BNE BLT BGE BLTU BGEU` | **implemented** | M1 |
| Jumps | `JAL JALR` | **implemented** | M1 |
| System | `FENCE` `ECALL` `EBREAK` | decoded as NOP (no traps) | M1 |
| Zicsr decode | `CSRRW/S/C` (+imm forms) | **reads implemented** for the counters above; write side-effects ignored (all implemented CSRs are read-only); unknown CSRs read 0; CSR reads in EX are not serialized against in-flight instructions | M4 |

## Multiply/divide — RV32M

| Instructions | Status | Landed at |
|---|---|---|
| `MUL MULH MULHSU MULHU DIV DIVU REM REMU` | **implemented** (pipeline: iterative multi-cycle `mdu.sv`, ~34 cycles, stalls EX; reference core: behavioural one-cycle via `riscv_pkg::mdu_func`; div-by-zero and `MIN_INT/-1` per spec) | M4 |

## CSRs — minimal Zicsr

| CSR | Purpose | Status | Landed at |
|---|---|---|---|
| `cycle` / `cycleh` (0xC00/0xC80) | cycle count, read-only | **implemented** | M4 |
| `instret` / `instreth` (0xC02/0xC82) | retired instructions (pipeline: bubbles from stalls/flushes are *not* counted), read-only | **implemented** | M4 |
| (non-standard) stall/mispredict counters | perf analysis | planned | M5 |

## Explicitly **not** implemented (by design)

Privileged spec beyond test needs, interrupts/exceptions beyond what tests
require, virtual memory, atomics (A), compressed (C), floating point (F/D),
and multi-core. See the README "Limitations" and the project spec for rationale.
