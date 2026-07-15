# Hazards and forwarding

> **Status:** current as of milestone **M3**.

## The three hazard classes, as they appear in this core

**Structural** — none by construction: Harvard memories (separate imem/dmem
ports), and the regfile write (WB) and reads (ID) are different ports.

**Data (RAW)** — an instruction needs a value a predecessor has computed but not
yet written back. Resolved by distance:

| Producer → consumer distance | Value lives in | Resolution |
|---|---|---|
| 1 (back-to-back) | EX/MEM register | forward EX/MEM → EX (`alu_y` or `pc+4`; never load data) |
| 1, producer is a **load** | dmem, this cycle | **stall one cycle**, then MEM/WB forward |
| 2 | MEM/WB register | forward MEM/WB → EX (final writeback value) |
| 3 | being written to regfile | WB → ID bypass (sync-write regfile) |
| ≥4 | register file | plain read |

Priority in the EX operand mux is youngest-first (EX/MEM over MEM/WB), per
source register, and `x0` is never forwarded. Forwarded values feed the ALU,
the branch comparator, the JALR target, and store data.

**Control** — branches/jumps resolve in EX. A taken redirect flushes the two
younger instructions (IF/ID, ID/EX → bubbles): 2-cycle taken penalty, 0-cycle
not-taken. M5's branch predictor attacks the taken penalty.

## Why the load-use stall is exactly one cycle

dmem reads are combinational in MEM, and MEM/WB registers the loaded value. A
consumer one behind a load stalls once; by the time it reaches EX the load is in
WB and MEM/WB forwarding supplies the data. Forwarding load data straight out of
MEM would remove the stall but put the entire dmem read on the EX critical path
— decision #014 keeps the classic single-bubble design.

## Where to see it proven

`docs/verification.md`: the ISA suite (dense with back-to-back hazards) passes
on the pipeline; randomized *hazardous* programs (RAW chains, load-use,
forwarded store data) match the single-cycle reference bit-for-bit; and
`hazard_demo` — which provably diverged on the un-forwarded M2 pipeline —
now matches at the hand-derived value.
