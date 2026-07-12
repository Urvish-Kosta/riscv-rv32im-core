#include "pipe.h"
    .section .text.init
    .globl _start
_start:
    lui  s1, %hi(scratch) ; P
    addi s1, s1, %lo(scratch) ; P
    li   t0, 0x111 ; P
    sw   t0, 0(s1) ; P
    li   t1, 0x222 ; P
    sw   t1, 4(s1) ; P
    li   t2, 0x7f ; P
    sb   t2, 8(s1) ; P
    lw   a0, 0(s1) ; P
    lw   a1, 4(s1) ; P
    lbu  a2, 8(s1) ; P
    lb   a3, 8(s1) ; P
    li   s0, 0 ; P
    xor  s0, s0, a0 ; P
    xor  s0, s0, a1 ; P
    xor  s0, s0, a2 ; P
    xor  s0, s0, a3 ; P
    lui  s2, %hi(tohost) ; P
    addi s2, s2, %lo(tohost) ; P
    sw   s0, 0(s2) ; P
1:  j 1b
    .section .data
    .align 4
scratch:
    .space 32
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost: .dword 0
    .globl fromhost
fromhost: .dword 0
