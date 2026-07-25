# Tracing tools

> **Status:** implemented at **M6**.

## Retire traces

Both cores emit a **retire trace** with `+trace_file=<path>`: one record per
architecturally committed instruction, in the same format regardless of
microarchitecture.

```
# cycle pc instr rd wdata memaddr memdata
43 80000014 026f0333 x7 00000001 - -
47 80000024 0071a023 - - 80000074 00000001
```

Two details make the traces directly comparable:

- **Retire-aligned store fields.** In the pipeline the data-memory write port
  (EX/MEM) belongs to a *different* instruction than the one retiring in WB.
  The cores therefore expose a separate retire-aligned store view, so each
  record describes exactly one instruction's effects. (The EX/MEM port is still
  what the harness watches for the HTIF exit, which must fire when the store
  actually commits.)
- **Identical end point.** Tracing stops when the halting store *retires*, so
  pipeline depth does not change the record count. Performance counters are
  snapshotted at the halt cycle, so the few drain cycles never inflate a
  measurement.

## `tools/trace_compare.py` — lockstep comparison

Compares a candidate trace against the reference core's trace record by record
and localizes the **first divergence** to an exact instruction, with context:

```
DIVERGENCE at retired instruction #1043 (architectural state)
   ok  #1040: pc=0x800001a4 addi t1, t1, 1        t1 <= 0x00000007
  ref  #1043: pc=0x800001b0 lw a0, 4(sp)          a0 <= 0xdeadbeef
  got  #1043: pc=0x800001b0 lw a0, 4(sp)          a0 <= 0x00000000
```

Control flow (`pc`, `instr`) must match unconditionally. For architectural
writes the tool understands one legitimate exception: reads of
`cycle`/`instret` and the performance counters **are** implementation-defined
and differ between a single-cycle core and a pipeline. Those are reported as
expected, and the destination register is marked *tainted* so later values
derived from it are classified as derived rather than flagged as bugs.
`--strict` disables the exception entirely.

Run it over everything with:

```sh
bash scripts/run_lockstep.sh          # ISA tests + compiled benchmarks, both cores
```

## `tools/trace_viewer.py` — annotated listing

Disassembles a trace and annotates each instruction with its effect. Because
each record carries its retire cycle, **gaps between records are exactly the
cycles lost to stalls and flushes**, and are called out inline:

```
    10       48 0x80000028  lw t4, 0(t3)                   t4 <= 0x00000001
                                                           .. 35 cycle(s) with no retire (stall/flush)
    11       84 0x8000002c  div t5, t4, t6                 t5 <= 0x00000001
```

That gap is a load-use stall (1 cycle) followed by the iterative divide
(34 cycles) — the microarchitecture's cost, visible per instruction.
`--stats` summarizes instruction mix and CPI over the traced window.
