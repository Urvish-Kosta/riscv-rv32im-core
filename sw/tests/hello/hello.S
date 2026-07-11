# =============================================================================
# hello.S  --  M0 end-to-end toolchain smoke test
#
# Purpose: prove that assemble -> link -> run-on-Spike works, before any RTL.
# It does a trivial computation (2 + 3 == 5) as a self-check, then signals
# PASS/FAIL to the host through the HTIF `tohost` mailbox and halts.
#
# HTIF exit convention (same as riscv-tests):
#   write value 1 to `tohost`  -> exit code 0 (PASS)
#   write value (N<<1)|1       -> exit code N (used later for FAIL codes)
#
# Build + run (see this folder's README.md for the exact commands):
#   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles \
#       -T ../../common/link.ld hello.S -o hello.elf
#   spike --isa=rv32im hello.elf ; echo "exit code = $?"
# =============================================================================

    .section .text.init
    .globl _start
_start:
    # --- trivial self-check: 2 + 3 must equal 5 ---------------------------
    li      t0, 2
    li      t1, 3
    add     t2, t0, t1          # t2 = 5
    li      t3, 5
    bne     t2, t3, fail        # if not 5, report failure

pass:
    li      a0, 1               # (0<<1)|1  -> exit code 0
    j       halt

fail:
    li      a0, 3               # (1<<1)|1  -> exit code 1
    j       halt

halt:
    la      t0, tohost
    sw      a0, 0(t0)           # notify host; Spike terminates on this write
1:  j       1b                  # spin until the simulator stops us

    # --- HTIF mailbox ------------------------------------------------------
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:
    .dword 0
    .globl fromhost
fromhost:
    .dword 0
