// xfail_hazard_demo.S -- DELIBERATELY hazardous (no NOP padding on the data
// chain). It documents the M2 contract: with no forwarding, the pipeline reads
// stale operands and MUST diverge from the single-cycle reference. The tohost
// address setup *is* padded so both cores still store a signature to compare.
// This becomes a passing (matching) test once M3 adds forwarding.
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
