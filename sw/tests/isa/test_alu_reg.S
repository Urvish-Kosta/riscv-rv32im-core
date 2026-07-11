#include "test.h"
    .section .text
    .globl test_body
test_body:
    li  t0, 20
    li  t1, 6
    add  t2, t0, t1
    CHECK_I(1, t2, 26)
    sub  t2, t0, t1
    CHECK_I(2, t2, 14)
    and  t2, t0, t1
    CHECK_I(3, t2, 4)
    or   t2, t0, t1
    CHECK_I(4, t2, 22)
    xor  t2, t0, t1
    CHECK_I(5, t2, 18)
    sll  t2, t0, t1
    CHECK_I(6, t2, 1280)
    srl  t2, t0, t1
    CHECK_I(7, t2, 0)
    li   t3, -20
    sra  t3, t3, t1
    CHECK_I(8, t3, -1)
    slt  t2, t1, t0
    CHECK_I(9, t2, 1)
    slt  t2, t0, t1
    CHECK_I(10, t2, 0)
    li   t4, -1
    sltu t2, t4, t0
    CHECK_I(11, t2, 0)
    sltu t2, t0, t4
    CHECK_I(12, t2, 1)
    ret
