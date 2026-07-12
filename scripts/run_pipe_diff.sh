#!/usr/bin/env bash
# =============================================================================
# run_pipe_diff.sh -- M2 differential verification.
#
# Builds each hazard-free pipeline program and runs it on BOTH cores:
#   * core_top  (single-cycle, the trusted reference)
#   * core_pipe (the 5-stage pipeline under test)
# and checks that the value each writes to `tohost` (a 32-bit result signature)
# is identical. pipe_smoke additionally has a hand-derived expected signature
# (0x0000000a), giving an oracle independent of both cores.
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ---- toolchain autodetect (riscv gcc, else clang cross) ----
RISCV_PREFIX=""
for p in riscv32-unknown-elf- riscv64-unknown-elf- riscv-none-elf-; do
  command -v "${p}gcc" >/dev/null 2>&1 && { RISCV_PREFIX="$p"; break; }
done
if [[ -n "$RISCV_PREFIX" ]]; then
  CC="${RISCV_PREFIX}gcc"; OBJCOPY="${RISCV_PREFIX}objcopy"
else
  CC="clang --target=riscv32-unknown-elf -fuse-ld=lld"; OBJCOPY="llvm-objcopy"
fi
CFLAGS="-march=rv32im -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -ffreestanding -Isw/tests/pipe -Wl,-T,sw/common/link.ld"

echo "== building both cores =="
make -C sim/verilator both >/dev/null
CORE=sim/verilator/obj_dir/Vcore_top
PIPE=sim/verilator/obj_dir_pipe/Vcore_pipe

B=sw/tests/pipe/build; mkdir -p "$B"
# expected hand-derived signatures (only where an independent value is known)
declare -A EXPECT=( [pipe_smoke]="0x0000000a" )

sig() { # run $1 sim on $2 hex, echo the tohost hex (ignore nonzero exit code)
  "$1" +hex="$2" +max_cycles=20000 2>&1 | grep -oE 'tohost=0x[0-9a-f]{8}' | cut -d= -f2
}

pass=0; fail=0
for src in sw/tests/pipe/*.S; do
  name="$(basename "$src" .S)"
  [[ "$name" == xfail_* ]] && continue
  $CC $CFLAGS "$src" -o "$B/$name.elf"
  $OBJCOPY -O binary "$B/$name.elf" "$B/$name.bin"
  python3 tools/bin2hex.py "$B/$name.bin" "$B/$name.hex"
  s_ref="$(sig "$CORE" "$B/$name.hex")"
  s_pipe="$(sig "$PIPE" "$B/$name.hex")"
  exp="${EXPECT[$name]:-}"
  printf "  %-12s ref=%s pipe=%s" "$name" "$s_ref" "$s_pipe"
  ok=1
  [[ "$s_ref" == "$s_pipe" ]] || ok=0
  if [[ -n "$exp" ]]; then printf " expect=%s" "$exp"; [[ "$s_pipe" == "$exp" ]] || ok=0; fi
  if [[ $ok -eq 1 && -n "$s_ref" ]]; then echo "  PASS"; ((pass++)); else echo "  FAIL"; ((fail++)); fi
done
# expected-divergence: hazardous code must differ (proves no forwarding yet)
$CC $CFLAGS sw/tests/pipe/xfail_hazard_demo.S -o "$B/xfail_hazard_demo.elf"
$OBJCOPY -O binary "$B/xfail_hazard_demo.elf" "$B/xfail_hazard_demo.bin"
python3 tools/bin2hex.py "$B/xfail_hazard_demo.bin" "$B/xfail_hazard_demo.hex"
xr="$(sig "$CORE" "$B/xfail_hazard_demo.hex")"; xp="$(sig "$PIPE" "$B/xfail_hazard_demo.hex")"
printf "  %-12s ref=%s pipe=%s" "xfail_hazard" "$xr" "$xp"
if [[ -n "$xr" && "$xr" != "$xp" ]]; then echo "  DIVERGES (expected, no fwd yet)"; ((pass++)); else echo "  UNEXPECTED MATCH"; ((fail++)); fi

echo "  -- randomized differential (committed seeds) --"
for seed in 1 2 3 4 5 6 7 8; do
  name="rand_s${seed}"
  python3 tools/gen_pipe_test.py "$seed" 40 > "$B/$name.S"
  $CC $CFLAGS "$B/$name.S" -o "$B/$name.elf"
  $OBJCOPY -O binary "$B/$name.elf" "$B/$name.bin"
  python3 tools/bin2hex.py "$B/$name.bin" "$B/$name.hex"
  s_ref="$(sig "$CORE" "$B/$name.hex")"
  s_pipe="$(sig "$PIPE" "$B/$name.hex")"
  printf "  %-12s ref=%s pipe=%s" "$name" "$s_ref" "$s_pipe"
  if [[ -n "$s_ref" && "$s_ref" == "$s_pipe" ]]; then echo "  PASS"; ((pass++)); else echo "  FAIL"; ((fail++)); fi
done
echo "  ------------------------------------------"
echo "  pipe-vs-reference: passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
