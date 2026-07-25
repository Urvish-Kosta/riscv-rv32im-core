#!/usr/bin/env bash
# =============================================================================
# run_lockstep.sh -- instruction-by-instruction retire-trace comparison.
#
# Runs every program on BOTH cores and compares their retire traces record by
# record with tools/trace_compare.py, which localizes the first divergence to
# the exact retired instruction. This is the same workflow as a Spike lockstep
# comparison, using the verified single-cycle core as the golden model (Spike
# itself remains the documented plan of record -- see docs/verification.md).
#
# Covers the self-checking ISA tests and the compiled C benchmark kernels; the
# latter are hundreds of thousands of instructions of real compiler output.
#
# Reads of cycle/instret and the performance counters legitimately differ
# between a single-cycle core and a pipeline; trace_compare classifies those
# (and values derived from them) as expected. Pass --strict to forbid even
# those.
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
STRICT="${1:-}"

RISCV_PREFIX=""
for p in riscv32-unknown-elf- riscv64-unknown-elf- riscv-none-elf-; do
  command -v "${p}gcc" >/dev/null 2>&1 && { RISCV_PREFIX="$p"; break; }
done
if [[ -n "$RISCV_PREFIX" ]]; then CC="${RISCV_PREFIX}gcc"; OBJCOPY="${RISCV_PREFIX}objcopy"
else CC="clang --target=riscv32-unknown-elf -fuse-ld=lld"; OBJCOPY="llvm-objcopy"; fi
CFLAGS="-march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -ffreestanding"
CFLAGS="$CFLAGS -Isw/common -Isw/bench -Wl,-T,sw/common/link.ld"

make -C sim/verilator both >/dev/null
CORE=sim/verilator/obj_dir/Vcore_top
PIPE=sim/verilator/obj_dir_pipe/Vcore_pipe
T=sw/tests/pipe/build; mkdir -p "$T"

# Build the ISA tests and the benchmarks if they are not built yet.
make -C sw/tests build >/dev/null
BB=sw/bench/build; mkdir -p "$BB"
for src in sw/bench/*.S sw/bench/*.c; do
  [[ -e "$src" ]] || continue
  n="$(basename "$src")"; n="${n%.*}"
  [[ -f "$BB/$n.hex" ]] && continue
  if [[ "$src" == *.c ]]; then $CC $CFLAGS -O2 sw/common/crt0.S "$src" -o "$BB/$n.elf"
  else $CC $CFLAGS "$src" -o "$BB/$n.elf"; fi
  $OBJCOPY -O binary "$BB/$n.elf" "$BB/$n.bin"
  python3 tools/bin2hex.py "$BB/$n.bin" "$BB/$n.hex"
done

pass=0; fail=0; total_instrs=0
run_one() { # name hexfile
  local n="$1" hex="$2" out
  "$CORE" +hex="$hex" +trace_file="$T/$n.ref.trace"  +max_cycles=5000000 >/dev/null 2>&1
  "$PIPE" +hex="$hex" +bp=gshare +trace_file="$T/$n.pipe.trace" +max_cycles=5000000 >/dev/null 2>&1
  if out="$(python3 tools/trace_compare.py $STRICT "$T/$n.ref.trace" "$T/$n.pipe.trace" 2>&1)"; then
    local line; line="$(tail -1 <<<"$out")"
    printf "  %-16s %s\n" "$n" "$line"
    local k; k="$(grep -oE '^MATCH: [0-9]+' <<<"$line" | grep -oE '[0-9]+')"
    [[ -n "$k" ]] && total_instrs=$((total_instrs + k))
    ((pass++))
  else
    printf "  %-16s DIVERGENCE\n" "$n"; sed 's/^/      /' <<<"$out" | head -10; ((fail++))
  fi
}

echo "== lockstep: self-checking ISA tests =="
for hex in sw/tests/build/*.hex; do run_one "$(basename "$hex" .hex)" "$hex"; done
echo "== lockstep: compiled benchmark kernels =="
for hex in "$BB"/*.hex; do run_one "$(basename "$hex" .hex)" "$hex"; done

echo "  ----------------------------------------"
echo "  programs: passed=$pass failed=$fail   retired instructions compared: $total_instrs"
[[ $fail -eq 0 ]]
