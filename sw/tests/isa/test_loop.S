#include "test.h"
    .section .text
    .globl test_body
test_body:
    # sum(1..10) == 55  (backward bne loop)
    li t0, 0
    li t1, 1
    li t2, 11
1:  add  t0, t0, t1
    addi t1, t1, 1
    bne  t1, t2, 1b
    CHECK_I(1, t0, 55)

    # countdown loop: 5 iterations (beq exit + backward j)
    li t3, 5
    li t4, 0
2:  beq  t3, x0, 3f
    addi t3, t3, -1
    addi t4, t4, 1
    j    2b
3:  CHECK_I(2, t4, 5)
    ret
