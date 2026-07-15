// hazard_demo.S -- deliberately hazardous (back-to-back RAW dependencies with
// no NOP padding). At M2 (no forwarding) this diverged from the single-cycle
// reference, proving the pipeline was un-forwarded; from M3 (forwarding +
// stalls + flush) it must match. History: M2 pipeline produced 0x0 here vs the
// reference's 0xc; M3 produces 0xc on both.
    .section .text.init
    .globl _start
_start:
    li   s0, 0
    li   t0, 5
    addi t1, t0, 1          // RAW on t0, back-to-back: pipe sees stale t0
    add  t2, t1, t1         // RAW on t1, back-to-back: pipe sees stale t1
    xor  s0, s0, t2
    nop; nop; nop
    lui  s1, %hi(tohost) ; nop; nop; nop
    addi s1, s1, %lo(tohost) ; nop; nop; nop
    sw   s0, 0(s1) ; nop; nop; nop
1:  j 1b
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost: .dword 0
    .globl fromhost
fromhost: .dword 0
