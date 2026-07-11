#!/usr/bin/env bash
# =============================================================================
# run_tests.sh  --  test entry point
#
# M1 primary check:
#   1) Build the Verilator core simulator and run the RV32I self-checking suite
#      (sw/tests). Expected values are derived from the ISA (independent oracle).
# Optional golden-model cross-check:
#   2) Spike rv32im "hello" -- runs only if Spike is installed.
#
# Each check is skipped (with a clear message) if a required tool is absent, so
# the script never hard-fails just because you have not installed everything.
# Lockstep Spike trace-compare + riscv-tests are the plan of record at M3.
# =============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
have() { command -v "$1" >/dev/null 2>&1; }
pass=0; skip=0; fail=0

# A RISC-V compiler is either a riscv*-unknown-elf GNU gcc, or clang (cross).
have_riscv_cc() {
  for g in riscv32-unknown-elf-gcc riscv64-unknown-elf-gcc riscv-none-elf-gcc; do
    have "$g" && return 0
  done
  have clang && return 0
  return 1
}

echo "== M1 test 1/2: RV32I self-checking suite (Verilator) =="
if have verilator && have_riscv_cc; then
  make -C "$ROOT/sim/verilator" >/dev/null
  if make -C "$ROOT/sw/tests" run; then echo "  -> PASS"; ((pass++)); else echo "  -> FAIL"; ((fail++)); fi
else
  echo "  -> SKIP (need verilator + a riscv gcc or clang; run scripts/build_toolchain.sh)"; ((skip++))
fi

echo
echo "== test 2/2: Spike hello (rv32im golden-model cross-check) =="
RISCV_GCC=""
for g in riscv32-unknown-elf-gcc riscv64-unknown-elf-gcc; do have "$g" && { RISCV_GCC="$g"; break; }; done
if [[ -n "$RISCV_GCC" ]] && have spike; then
  H="$ROOT/sw/tests/hello"
  "$RISCV_GCC" -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles \
      -T "$ROOT/sw/common/link.ld" "$H/hello.S" -o "$H/hello.elf"
  if spike --isa=rv32im "$H/hello.elf"; then echo "  -> PASS (exit 0)"; ((pass++)); else echo "  -> FAIL"; ((fail++)); fi
else
  echo "  -> SKIP (optional; needs riscv gcc + spike)"; ((skip++))
fi

echo
echo "== summary: pass=$pass skip=$skip fail=$fail =="
(( fail == 0 ))
