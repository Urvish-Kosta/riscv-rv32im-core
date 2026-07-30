#!/usr/bin/env python3
"""trace_viewer.py -- human-readable view of a retire trace.

Disassembles each retired instruction and annotates it with its architectural
effect. Because the trace records the cycle each instruction retired, gaps
between consecutive records are exactly the cycles the pipeline lost to stalls
and flushes -- those are called out inline, which makes the cost of a load-use
hazard, a multi-cycle multiply, or a branch mispredict directly visible.

    python3 trace_viewer.py run.trace [--head N] [--pc 0x8000...] [--stats]
"""
import argparse
import sys
from collections import Counter

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import rvdisasm as D  # noqa: E402


def load(path):
    recs = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            p = line.split()
            if len(p) != 7:
                continue
            recs.append({
                "cycle": int(p[0]), "pc": int(p[1], 16), "instr": int(p[2], 16),
                "rd": p[3], "wdata": p[4], "memaddr": p[5], "memdata": p[6],
            })
    return recs


def classify(word):
    op, f7 = D.opcode(word), D.funct7(word)
    if op == 0x63:                       return "branch"
    if op in (0x6F, 0x67):               return "jump"
    if op == 0x03:                       return "load"
    if op == 0x23:                       return "store"
    if op == 0x33 and f7 == 0x01:        return "muldiv"
    if op == 0x73 and D.funct3(word):    return "csr"
    return "alu"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("trace")
    ap.add_argument("--head", type=int, default=0, help="show only the first N instructions")
    ap.add_argument("--pc", help="show only records at this PC (hex)")
    ap.add_argument("--stats", action="store_true", help="print a summary instead of the listing")
    a = ap.parse_args()

    recs = load(a.trace)
    if not recs:
        print("error: empty or unreadable trace", file=sys.stderr)
        return 2

    if a.stats:
        kinds = Counter(classify(r["instr"]) for r in recs)
        span = recs[-1]["cycle"] - recs[0]["cycle"] + 1
        lost = span - len(recs)
        print(f"retired instructions : {len(recs)}")
        print(f"cycle span           : {span}")
        print(f"cycles not retiring  : {lost} ({100.0 * lost / span:.1f}%)")
        print(f"CPI over this window : {span / len(recs):.3f}")
        print("instruction mix      :")
        for k, v in kinds.most_common():
            print(f"    {k:<8} {v:6d}  {100.0 * v / len(recs):5.1f}%")
        return 0

    want_pc = int(a.pc, 16) if a.pc else None
    shown = 0
    prev_cycle = None
    print(f"{'#':>6} {'cycle':>8} {'pc':>10}  {'instruction':<30} effect")
    for i, r in enumerate(recs):
        if want_pc is not None and r["pc"] != want_pc:
            continue
        gap = 0 if prev_cycle is None else r["cycle"] - prev_cycle - 1
        prev_cycle = r["cycle"]
        if gap > 0 and want_pc is None:
            print(f"{'':>6} {'':>8} {'':>10}  {'':<30} .. {gap} cycle(s) with no retire "
                  f"(stall/flush)")
        eff = ""
        if r["rd"] != "-":
            eff = f"{D.REG[int(r['rd'][1:])]} <= 0x{r['wdata']}"
        if r["memaddr"] != "-":
            eff += ("  " if eff else "") + f"mem[0x{r['memaddr']}] <= 0x{r['memdata']}"
        print(f"{i:>6} {r['cycle']:>8} 0x{r['pc']:08x}  "
              f"{D.disasm(r['instr'], r['pc']):<30} {eff}")
        shown += 1
        if a.head and shown >= a.head:
            print(f"... ({len(recs) - shown} more)")
            break
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        # Downstream closed the pipe (e.g. `| head`): exit quietly, as a
        # well-behaved CLI tool should.
        import os
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        raise SystemExit(0)
