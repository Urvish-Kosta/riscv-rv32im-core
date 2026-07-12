#include "pipe.h"
    .section .text.init
    .globl _start
_start:
    li   t0, 20 ; P
    li   t1, 6  ; P
    li   s0, 0  ; P
    add  t2, t0, t1 ; P
    xor  s0, s0, t2 ; P
    sub  t2, t0, t1 ; P
    xor  s0, s0, t2 ; P
    and  t2, t0, t1 ; P
    xor  s0, s0, t2 ; P
    or   t2, t0, t1 ; P
    xor  s0, s0, t2 ; P
    sll  t2, t0, t1 ; P
    xor  s0, s0, t2 ; P
    srl  t2, t0, t1 ; P
    xor  s0, s0, t2 ; P
    li   t3, -20 ; P
    sra  t3, t3, t1 ; P
    xor  s0, s0, t3 ; P
    slt  t2, t1, t0 ; P
    xor  s0, s0, t2 ; P
    sltu t2, t0, t1 ; P
    xor  s0, s0, t2 ; P
    lui  s1, %hi(tohost) ; P
    addi s1, s1, %lo(tohost) ; P
    sw   s0, 0(s1) ; P
1:  j 1b
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost: .dword 0
    .globl fromhost
fromhost: .dword 0
