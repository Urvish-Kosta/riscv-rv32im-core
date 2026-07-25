#!/usr/bin/env bash
# =============================================================================
# run_benchmarks.sh -- measured CPI / branch statistics (M5, extended at M6).
#
# Builds every benchmark in sw/bench/ (assembly kernels and C kernels), runs
# each under all three branch-predictor modes, and prints the measured numbers
# reported by the harness. Every figure comes from the run this script just
# performed; nothing is estimated.
#
# Benchmarks are self-checking: a run is only reported if it produced the
# correct architectural result (the C kernels check against golden values
# derived independently on the host -- see sw/bench/expected.h).
#
#   ./scripts/run_benchmarks.sh                # human-readable table
#   ./scripts/run_benchmarks.sh --csv out.csv  # + machine-readable results
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CSV=""
[[ "${1:-}" == "--csv" ]] && CSV="${2:?--csv needs a path}"

RISCV_PREFIX=""
for p in riscv32-unknown-elf- riscv64-unknown-elf- riscv-none-elf-; do
  command -v "${p}gcc" >/dev/null 2>&1 && { RISCV_PREFIX="$p"; break; }
done
if [[ -n "$RISCV_PREFIX" ]]; then
  CC="${RISCV_PREFIX}gcc"; OBJCOPY="${RISCV_PREFIX}objcopy"
else
  CC="clang --target=riscv32-unknown-elf -fuse-ld=lld"; OBJCOPY="llvm-objcopy"
fi
CFLAGS="-march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -ffreestanding"
CFLAGS="$CFLAGS -Isw/common -Isw/bench -Wl,-T,sw/common/link.ld"

make -C sim/verilator pipe >/dev/null
PIPE=sim/verilator/obj_dir_pipe/Vcore_pipe
B=sw/bench/build; mkdir -p "$B"

[[ -n "$CSV" ]] && echo "benchmark,mode,cycles,retired,cpi,stall_loaduse,stall_mdu,redirects,branches,taken,mispredicts" > "$CSV"

fail=0
printf "%-14s %-8s %10s %9s %7s %9s %9s %7s %6s %7s\n" \
  benchmark mode cycles retired CPI ld-stall mdu-stall br misp misp%
printf '%.0s-' {1..96}; echo
for src in sw/bench/*.S sw/bench/*.c; do
  [[ -e "$src" ]] || continue
  name="$(basename "$src")"; name="${name%.*}"
  if [[ "$src" == *.c ]]; then
    $CC $CFLAGS -O2 sw/common/crt0.S "$src" -o "$B/$name.elf" || { echo "$name: BUILD FAILED"; fail=1; continue; }
  else
    $CC $CFLAGS "$src" -o "$B/$name.elf" || { echo "$name: BUILD FAILED"; fail=1; continue; }
  fi
  $OBJCOPY -O binary "$B/$name.elf" "$B/$name.bin"
  python3 tools/bin2hex.py "$B/$name.bin" "$B/$name.hex"
  for mode in off bimodal gshare; do
    out="$("$PIPE" +hex="$B/$name.hex" +bp=$mode +max_cycles=5000000 2>&1)"
    if ! grep -q "PASS" <<<"$out"; then
      echo "$name/$mode: FAILED SELF-CHECK"; fail=1; continue
    fi
    perf="$(grep -oE '\[perf\].*' <<<"$out")"
    g() { grep -oE "$1=[0-9.]+" <<<"$perf" | cut -d= -f2; }
    cyc=$(g cycles); ret=$(g retired); cpi=$(g cpi)
    lds=$(g stall_loaduse); mds=$(g stall_mdu); rdr=$(g redirects)
    br=$(g branches); tk=$(g taken); mp=$(g br_mispred)
    pct="-"; [[ "$br" -gt 0 ]] && pct=$(python3 -c "print(f'{100*$mp/$br:.1f}')")
    printf "%-14s %-8s %10s %9s %7s %9s %9s %7s %6s %6s%%\n" \
      "$name" "$mode" "$cyc" "$ret" "$cpi" "$lds" "$mds" "$br" "$mp" "$pct"
    [[ -n "$CSV" ]] && echo "$name,$mode,$cyc,$ret,$cpi,$lds,$mds,$rdr,$br,$tk,$mp" >> "$CSV"
  done
done
[[ -n "$CSV" ]] && echo && echo "wrote $CSV"
exit $fail
