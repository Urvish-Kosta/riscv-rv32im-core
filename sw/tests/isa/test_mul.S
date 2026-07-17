#include "test.h"
    .section .text
    .globl test_body
test_body:
    li   t0, 7
    li   t1, 6
    mul  t2, t0, t1
    CHECK_I(1, t2, 42)
    li   t0, -7
    mul  t2, t0, t1                 # -42
    CHECK_I(2, t2, -42)
    li   t0, 0x10000
    mul  t2, t0, t0                 # 2^32 -> low word 0
    CHECK_I(3, t2, 0)
    mulhu t2, t0, t0                # 2^32 -> high word 1
    CHECK_I(4, t2, 1)
    li   t0, 0x40000000
    li   t1, 4
    mulh t2, t0, t1                 # 2^30 * 4 = 2^32 -> high 1
    CHECK_I(5, t2, 1)
    li   t0, -7
    li   t1, 6
    mulh t2, t0, t1                 # -42 -> high word all ones
    CHECK_I(6, t2, 0xffffffff)
    li   t0, -1
    mulhu t2, t0, t0                # (2^32-1)^2 -> high 0xfffffffe
    CHECK_I(7, t2, 0xfffffffe)
    li   t0, -1
    li   t1, 2
    mulhsu t2, t0, t1               # (-1)*2 = -2 -> high all ones
    CHECK_I(8, t2, 0xffffffff)
    li   t0, 2
    li   t1, -1                     # unsigned 0xffffffff
    mulhsu t2, t0, t1               # 2*(2^32-1) = 0x1_fffffffe -> high 1
    CHECK_I(9, t2, 1)
    li   t0, 0x80000000
    mulh t2, t0, t0                 # (-2^31)^2 = 2^62 -> high 0x40000000
    CHECK_I(10, t2, 0x40000000)
    # back-to-back RAW through the M unit
    li   t0, 3
    mul  t1, t0, t0                 # 9
    mul  t2, t1, t1                 # 81
    addi t3, t2, 1
    CHECK_I(11, t3, 82)
    ret
