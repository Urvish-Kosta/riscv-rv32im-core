#!/usr/bin/env bash
# =============================================================================
# make_waves.sh -- regenerate the committed waveform in sim/waves/.
#
# Builds sw/tests/pipe/hazard_showcase.S -- a short program that exercises
# every hazard class in a few dozen cycles -- runs it on the pipelined core
# with VCD dumping enabled, and stores the result as
# sim/waves/hazard_showcase.vcd. Open it with:
#
#     gtkwave sim/waves/hazard_showcase.vcd sim/waves/hazard_showcase.gtkw
#
# The .gtkw save file pre-selects the fetch/redirect, stall, forwarding,
# retire, and performance-counter signals, so the hazards are visible without
# hunting through the hierarchy.
# =============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RISCV_PREFIX=""
for p in riscv32-unknown-elf- riscv64-unknown-elf- riscv-none-elf-; do
  command -v "${p}gcc" >/dev/null 2>&1 && { RISCV_PREFIX="$p"; break; }
done
if [[ -n "$RISCV_PREFIX" ]]; then CC="${RISCV_PREFIX}gcc"; OBJCOPY="${RISCV_PREFIX}objcopy"
else CC="clang --target=riscv32-unknown-elf -fuse-ld=lld"; OBJCOPY="llvm-objcopy"; fi

make -C sim/verilator pipe >/dev/null
B=sw/tests/pipe/build; mkdir -p "$B"
$CC -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -ffreestanding \
    -Wl,-T,sw/common/link.ld sw/tests/pipe/hazard_showcase.S -o "$B/hazard_showcase.elf"
$OBJCOPY -O binary "$B/hazard_showcase.elf" "$B/hazard_showcase.bin"
python3 tools/bin2hex.py "$B/hazard_showcase.bin" "$B/hazard_showcase.hex"

cd sim/verilator
./obj_dir_pipe/Vcore_pipe +hex="../../$B/hazard_showcase.hex" +bp=gshare +vcd +max_cycles=200
mv -f wave.vcd ../waves/hazard_showcase.vcd
echo "wrote sim/waves/hazard_showcase.vcd"
