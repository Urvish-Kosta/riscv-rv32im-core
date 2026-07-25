#!/usr/bin/env python3
"""trace_compare.py -- lockstep comparison of two retire traces.

Compares the pipelined core against the verified single-cycle reference
instruction-by-instruction and localizes the FIRST divergence to the exact
retired instruction -- the same workflow as a Spike lockstep comparison, with
the single-cycle core standing in as the golden model (Spike is the documented
plan of record; see docs/verification.md).

A retire record is:  cycle pc instr rd wdata memaddr memdata
Cycle numbers are expected to differ between implementations and are ignored.

Timing-dependent CSRs
---------------------
Reads of `cycle`/`instret` and the performance counters legitimately return
different values on a pipeline than on a single-cycle core: they are
implementation-defined, not architectural state. With --allow-csr (default)
such divergences are reported as EXPECTED, and the destination register is
marked *tainted* so later differences derived from it are classified as
"derived from a timing CSR" rather than reported as core bugs. Use
--strict to disable this and require bit-exact equality everywhere.

    python3 trace_compare.py ref.trace pipe.trace [--strict] [--context N]
"""
import argparse
import sys

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
                "cycle": int(p[0]),
                "pc": int(p[1], 16),
                "instr": int(p[2], 16),
                "rd": p[3],
                "wdata": p[4],
                "memaddr": p[5],
                "memdata": p[6],
            })
    return recs


def fmt(r):
    s = f"pc=0x{r['pc']:08x} {D.disasm(r['instr'], r['pc']):<28}"
    if r["rd"] != "-":
        s += f" {r['rd']}<={r['wdata']}"
    if r["memaddr"] != "-":
        s += f" mem[{r['memaddr']}]<={r['memdata']}"
    return s


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reference", help="golden retire trace (single-cycle core)")
    ap.add_argument("candidate", help="retire trace under test (pipeline)")
    ap.add_argument("--strict", action="store_true",
                    help="require bit-exact equality; do not excuse timing CSRs")
    ap.add_argument("--context", type=int, default=3,
                    help="instructions of context to show around a divergence")
    a = ap.parse_args()

    ref, cand = load(a.reference), load(a.candidate)
    if not ref or not cand:
        print("error: empty trace(s)", file=sys.stderr)
        return 2

    tainted = set()          # register *indices* holding timing-dependent values
    expected = 0             # divergences excused as timing-CSR related
    n = min(len(ref), len(cand))

    for i in range(n):
        r, c = ref[i], cand[i]

        # Control flow must match exactly, always.
        if r["pc"] != c["pc"] or r["instr"] != c["instr"]:
            print(f"DIVERGENCE at retired instruction #{i} (control flow)")
            lo = max(0, i - a.context)
            for j in range(lo, i):
                print(f"   ok  #{j}: {fmt(ref[j])}")
            print(f"  ref  #{i}: {fmt(r)}")
            print(f"  got  #{i}: {fmt(c)}")
            return 1

        w    = r["instr"]
        rdi  = int(r["rd"][1:]) if r["rd"] != "-" else None
        srcs = D.source_regs(w)
        same = (r["rd"] == c["rd"] and r["wdata"] == c["wdata"]
                and r["memaddr"] == c["memaddr"] and r["memdata"] == c["memdata"])

        # --- taint dataflow (independent of whether the values happened to
        # match: a cycle counter read is timing-dependent even when the two
        # implementations coincidentally agree on it) ---
        if not a.strict:
            if D.is_csr_read(w):
                if rdi is not None:
                    tainted.add(rdi)
            elif srcs & tainted:
                if rdi is not None:
                    tainted.add(rdi)
            elif rdi is not None:
                tainted.discard(rdi)      # freshly computed clean value

        if same:
            continue

        if not a.strict and D.is_csr_read(w):
            expected += 1
            print(f"  expected #{i}: timing CSR read differs -- {fmt(r)}  vs  "
                  f"{c['rd']}<={c['wdata']}")
            continue

        if not a.strict and (srcs & tainted):
            names = sorted(D.REG[x] for x in (srcs & tainted))
            expected += 1
            print(f"  expected #{i}: derived from a timing CSR "
                  f"(reads {names}) -- {fmt(r)}  vs  {c['rd']}<={c['wdata']}")
            continue

        print(f"DIVERGENCE at retired instruction #{i} (architectural state)")
        lo = max(0, i - a.context)
        for j in range(lo, i):
            print(f"   ok  #{j}: {fmt(ref[j])}")
        print(f"  ref  #{i}: {fmt(r)}")
        print(f"  got  #{i}: {fmt(c)}")
        return 1

    if len(ref) != len(cand):
        print(f"DIVERGENCE: trace lengths differ after {n} matching instructions "
              f"(reference {len(ref)}, candidate {len(cand)})")
        return 1

    msg = f"MATCH: {n} retired instructions identical"
    if expected:
        msg += f" ({expected} timing-CSR difference(s) excused; use --strict to fail on them)"
    print(msg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
