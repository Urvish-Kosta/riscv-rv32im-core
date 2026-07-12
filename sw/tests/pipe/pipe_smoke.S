#include "pipe.h"
    .section .text.init
    .globl _start
_start:
    li   t0, 10 ; P
    li   t1, 3  ; P
    add  t2, t0, t1 ; P          # 13
    sub  t3, t0, t1 ; P          # 7
    xor  s0, t2, t3 ; P          # 13 ^ 7 = 10  (0x0000000a)  <-- expected signature
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
