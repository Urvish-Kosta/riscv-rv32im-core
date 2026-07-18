#!/usr/bin/env bash
# =============================================================================
# run_pipe_diff.sh -- pipeline differential verification (M3).
#
# The pipeline (core_pipe: forwarding + load-use stall + branch flush) is
# checked against the single-cycle reference (core_top), which is itself
# verified against hand-derived ISA values. Both run the same image and write a
# 32-bit signature to `tohost`; signatures must match on every program:
#   * directed hazard-free programs (M2 set, one with a hand-derived anchor)
#   * hazard_demo -- dense back-to-back RAW chains (diverged at M2, must match now)
#   * randomized hazard-free programs (committed seeds)
#   * randomized HAZARDOUS programs (no padding; RAW chains, load-use, stores)
# Finally the full M1 self-checking ISA suite is run directly on the pipeline.
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RISCV_PREFIX=""
for p in riscv32-unknown-elf- riscv64-unknown-elf- riscv-none-elf-; do
  command -v "${p}gcc" >/dev/null 2>&1 && { RISCV_PREFIX="$p"; break; }
done
if [[ -n "$RISCV_PREFIX" ]]; then
  CC="${RISCV_PREFIX}gcc"; OBJCOPY="${RISCV_PREFIX}objcopy"
else
  CC="clang --target=riscv32-unknown-elf -fuse-ld=lld"; OBJCOPY="llvm-objcopy"
fi
CFLAGS="-march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -ffreestanding -Isw/tests/pipe -Wl,-T,sw/common/link.ld"

echo "== building both cores =="
make -C sim/verilator both >/dev/null
CORE=sim/verilator/obj_dir/Vcore_top
PIPE=sim/verilator/obj_dir_pipe/Vcore_pipe

B=sw/tests/pipe/build; mkdir -p "$B"
declare -A EXPECT=( [pipe_smoke]="0x0000000a" [hazard_demo]="0x0000000c" )

sig() { # binary hex [extra-args]
  "$1" +hex="$2" ${3:-} +max_cycles=40000 2>&1 | grep -oE 'tohost=0x[0-9a-f]{8}' | cut -d= -f2; }

pass=0; fail=0
check() { # name hexfile  -- pipeline is checked in ALL predictor modes
  local name="$1" hex="$2"
  local s_ref s_p exp ok=1 mode
  s_ref="$(sig "$CORE" "$hex")"
  exp="${EXPECT[$name]:-}"
  printf "  %-14s ref=%s" "$name" "$s_ref"
  [[ -n "$s_ref" ]] || ok=0
  for mode in off bimodal gshare; do
    s_p="$(sig "$PIPE" "$hex" "+bp=$mode")"
    printf " %s=%s" "$mode" "$s_p"
    [[ "$s_p" == "$s_ref" ]] || ok=0
  done
  if [[ -n "$exp" ]]; then printf " expect=%s" "$exp"; [[ "$s_ref" == "$exp" ]] || ok=0; fi
  if [[ $ok -eq 1 ]]; then echo "  PASS"; ((pass++)); else echo "  FAIL"; ((fail++)); fi
}

build_S() { # src.S -> hex path echoed
  local src="$1" name; name="$(basename "$src" .S)"
  $CC $CFLAGS "$src" -o "$B/$name.elf"
  $OBJCOPY -O binary "$B/$name.elf" "$B/$name.bin"
  python3 tools/bin2hex.py "$B/$name.bin" "$B/$name.hex"
  echo "$B/$name.hex"
}

echo "  -- directed --"
for src in sw/tests/pipe/*.S; do
  check "$(basename "$src" .S)" "$(build_S "$src")"
done

echo "  -- randomized hazard-free (committed seeds) --"
for seed in 1 2 3 4; do
  python3 tools/gen_pipe_test.py "$seed" 40 > "$B/rand_s${seed}.S"
  check "rand_s${seed}" "$(build_S "$B/rand_s${seed}.S")"
done

echo "  -- randomized HAZARDOUS (committed seeds) --"
for seed in 11 12 13 14 15 16 17 18; do
  python3 tools/gen_pipe_test.py "$seed" 60 --hazard > "$B/hz_s${seed}.S"
  check "hz_s${seed}" "$(build_S "$B/hz_s${seed}.S")"
done

echo "  -- pipeline-only directed (perf CSRs) --"
$CC $CFLAGS -Isw/common sw/common/crt.S sw/tests/pipeonly/test_perfcsr.S -o "$B/perfcsr.elf"
$OBJCOPY -O binary "$B/perfcsr.elf" "$B/perfcsr.bin"
python3 tools/bin2hex.py "$B/perfcsr.bin" "$B/perfcsr.hex"
if "$PIPE" +hex="$B/perfcsr.hex" +max_cycles=40000 >/dev/null 2>&1; then
  echo "  test_perfcsr   PASS"; ((pass++))
else
  echo "  test_perfcsr   FAIL"; ((fail++))
fi

for mode in off bimodal gshare; do
  echo "  -- ISA suite on the PIPELINE (+bp=$mode) --"
  if make -C sw/tests run SIM=../../sim/verilator/obj_dir_pipe/Vcore_pipe SIMFLAGS="+bp=$mode" | sed 's/^/  /' | tail -2 | head -1; then
    ((pass++))
  else
    echo "  ISA-on-pipeline ($mode) FAILED"; ((fail++))
  fi
done

echo "  ------------------------------------------"
echo "  pipeline verification: passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
