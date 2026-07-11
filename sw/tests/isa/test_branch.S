#include "test.h"
    .section .text
    .globl test_body
test_body:
    li t0, 5
    li t1, 5
    li t2, 7
    li gp, 1
    beq t0, t1, 1f
    j _fail
1:  li gp, 2
    beq t0, t2, _fail
    li gp, 3
    bne t0, t2, 2f
    j _fail
2:  li gp, 4
    bne t0, t1, _fail
    li t3, -1
    li t4, 1
    li gp, 5
    blt t3, t4, 3f
    j _fail
3:  li gp, 6
    blt t4, t3, _fail
    li gp, 7
    bge t4, t3, 4f
    j _fail
4:  li gp, 8
    bge t3, t4, _fail
    li a1, 1
    li a2, -1
    li gp, 9
    bltu a1, a2, 5f
    j _fail
5:  li gp, 10
    bltu a2, a1, _fail
    li gp, 11
    bgeu a2, a1, 6f
    j _fail
6:  li gp, 12
    bgeu a1, a2, _fail
    ret
