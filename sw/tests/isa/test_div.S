#include "test.h"
    .section .text
    .globl test_body
test_body:
    li   t0, 42
    li   t1, 6
    div  t2, t0, t1
    CHECK_I(1, t2, 7)
    li   t0, -42
    div  t2, t0, t1
    CHECK_I(2, t2, -7)
    li   t1, -6
    div  t2, t0, t1                 # -42 / -6 = 7
    CHECK_I(3, t2, 7)
    li   t0, 42
    div  t2, t0, t1                 # 42 / -6 = -7
    CHECK_I(4, t2, -7)
    li   t0, 7
    li   t1, 2
    div  t2, t0, t1                 # trunc toward zero
    CHECK_I(5, t2, 3)
    rem  t2, t0, t1
    CHECK_I(6, t2, 1)
    li   t0, -7
    div  t2, t0, t1                 # -7/2 = -3
    CHECK_I(7, t2, -3)
    rem  t2, t0, t1                 # -7%2 = -1
    CHECK_I(8, t2, -1)
    li   t1, -2
    rem  t2, t0, t1                 # -7 % -2 = -1
    CHECK_I(9, t2, -1)
    li   t0, 7
    rem  t2, t0, t1                 # 7 % -2 = 1
    CHECK_I(10, t2, 1)
    # unsigned
    li   t0, -1                     # 0xffffffff
    li   t1, 2
    divu t2, t0, t1
    CHECK_I(11, t2, 0x7fffffff)
    remu t2, t0, t1
    CHECK_I(12, t2, 1)
    li   t0, 7
    li   t1, 3
    divu t2, t0, t1
    CHECK_I(13, t2, 2)
    remu t2, t0, t1
    CHECK_I(14, t2, 1)
    # divide by zero (defined results, no trap)
    li   t0, 5
    li   t1, 0
    div  t2, t0, t1
    CHECK_I(15, t2, -1)
    divu t2, t0, t1
    CHECK_I(16, t2, 0xffffffff)
    rem  t2, t0, t1
    CHECK_I(17, t2, 5)
    remu t2, t0, t1
    CHECK_I(18, t2, 5)
    # signed overflow: MIN_INT / -1
    li   t0, 0x80000000
    li   t1, -1
    div  t2, t0, t1
    CHECK_I(19, t2, 0x80000000)
    rem  t2, t0, t1
    CHECK_I(20, t2, 0)
    ret
