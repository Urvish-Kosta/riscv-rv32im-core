#include "test.h"
    .section .text
    .globl test_body
test_body:
    li    t0, 5
    addi  t1, t0, 7
    CHECK_I(1, t1, 12)
    addi  t1, t0, -8
    CHECK_I(2, t1, -3)
    ori   t1, t0, 0x2
    CHECK_I(3, t1, 7)
    andi  t1, t0, 0x6
    CHECK_I(4, t1, 4)
    xori  t1, t0, 0x1
    CHECK_I(5, t1, 4)
    slli  t1, t0, 3
    CHECK_I(6, t1, 40)
    srli  t1, t0, 1
    CHECK_I(7, t1, 2)
    li    t2, -16
    srai  t1, t2, 2
    CHECK_I(8, t1, -4)
    slti  t1, t0, 10
    CHECK_I(9, t1, 1)
    slti  t1, t0, 3
    CHECK_I(10, t1, 0)
    sltiu t1, t0, 10
    CHECK_I(11, t1, 1)
    li    t3, -1
    sltiu t1, t3, 1
    CHECK_I(12, t1, 0)
    ret
