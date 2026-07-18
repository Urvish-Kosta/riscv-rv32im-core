#!/usr/bin/env bash
# =============================================================================
# run_benchmarks.sh -- measured CPI / branch statistics (M5).
#
# Builds the pipeline, runs each benchmark in sw/bench/ under all three branch
# predictor modes (off / bimodal / gshare) and prints the *measured* numbers
# from the simulation harness. Every figure is observed in the run performed by
# this script; nothing is estimated. Benchmarks are self-checking -- a run only
# counts if its architectural result is correct (exit PASS).
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
CFLAGS="-march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -ffreestanding -Wl,-T,sw/common/link.ld"

make -C sim/verilator pipe >/dev/null
PIPE=sim/verilator/obj_dir_pipe/Vcore_pipe
B=sw/bench/build; mkdir -p "$B"

fail=0
printf "%-12s %-8s %10s %8s %7s %9s %9s %6s %6s %7s\n" \
  bench mode cycles retired CPI ld-stall mdu-stall br misp misp%
for src in sw/bench/*.S; do
  name="$(basename "$src" .S)"
  $CC $CFLAGS "$src" -o "$B/$name.elf"
  $OBJCOPY -O binary "$B/$name.elf" "$B/$name.bin"
  python3 tools/bin2hex.py "$B/$name.bin" "$B/$name.hex"
  for mode in off bimodal gshare; do
    out="$("$PIPE" +hex="$B/$name.hex" +bp=$mode +max_cycles=2000000 2>&1)"
    if ! grep -q "PASS" <<<"$out"; then
      echo "$name/$mode: FAILED SELF-CHECK"; fail=1; continue
    fi
    perf="$(grep -oE '\[perf\].*' <<<"$out")"
    cyc=$(grep -oE 'cycles=[0-9]+' <<<"$perf" | cut -d= -f2)
    ret=$(grep -oE 'retired=[0-9]+' <<<"$perf" | cut -d= -f2)
    cpi=$(grep -oE 'cpi=[0-9.]+' <<<"$perf" | cut -d= -f2)
    lds=$(grep -oE 'stall_loaduse=[0-9]+' <<<"$perf" | cut -d= -f2)
    mds=$(grep -oE 'stall_mdu=[0-9]+' <<<"$perf" | cut -d= -f2)
    br=$(grep -oE 'branches=[0-9]+' <<<"$perf" | cut -d= -f2)
    mp=$(grep -oE 'br_mispred=[0-9]+' <<<"$perf" | cut -d= -f2)
    pct="-"
    [[ "$br" -gt 0 ]] && pct=$(python3 -c "print(f'{100*$mp/$br:.1f}')")
    printf "%-12s %-8s %10s %8s %7s %9s %9s %6s %6s %6s%%\n" \
      "$name" "$mode" "$cyc" "$ret" "$cpi" "$lds" "$mds" "$br" "$mp" "$pct"
  done
done
exit $fail
