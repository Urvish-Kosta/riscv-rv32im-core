# ISA Support

This file states **exactly** what is implemented in the RTL at any given time.
It is the single source of truth for scope honesty — no claim of full-ISA or
privileged-spec support is made anywhere in this repo beyond what this table shows.

**As of milestone M1: the full RV32I base integer set is implemented** in a
single-cycle datapath and verified by self-checking directed tests (see
`docs/verification.md`). RV32M and the CSRs remain planned. A group is marked
*implemented* only once it is built and passes its tests.

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
| System | `FENCE` `ECALL` `EBREAK` | decoded as NOP (no CSR/trap yet) | M1 |

## Multiply/divide — RV32M

| Instructions | Status | Landed at |
|---|---|---|
| `MUL MULH MULHSU MULHU DIV DIVU REM REMU` (multi-cycle) | planned | M4 |

## CSRs — minimal Zicsr

| CSR | Purpose | Status | Landed at |
|---|---|---|---|
| `mcycle` / `mcycleh` | cycle count | planned | M4 |
| `minstret` / `minstreth` | instructions retired | planned | M4 |
| (non-standard) stall/mispredict counters | perf analysis | planned | M5 |

## Explicitly **not** implemented (by design)

Privileged spec beyond test needs, interrupts/exceptions beyond what tests
require, virtual memory, atomics (A), compressed (C), floating point (F/D),
and multi-core. See the README "Limitations" and the project spec for rationale.
