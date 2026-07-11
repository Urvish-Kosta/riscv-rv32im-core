#include "test.h"
    .section .text
    .globl test_body
test_body:
    la  t0, scratch
    li  t1, 0xdeadbeef
    sw  t1, 0(t0)
    lw  t2, 0(t0)
    CHECK_I(1, t2, 0xdeadbeef)

    li  t1, 0x000000f5
    sb  t1, 4(t0)
    lbu t2, 4(t0)
    CHECK_I(2, t2, 0xf5)
    lb  t2, 4(t0)
    CHECK_I(3, t2, -11)

    li  t1, 0x0000abcd
    sh  t1, 8(t0)
    lhu t2, 8(t0)
    CHECK_I(4, t2, 0xabcd)
    lh  t2, 8(t0)
    CHECK_I(5, t2, 0xffffabcd)

    li  t1, 0x11223344
    sw  t1, 12(t0)
    li  t1, 0x99
    sb  t1, 12(t0)
    lw  t2, 12(t0)
    CHECK_I(6, t2, 0x11223399)
    sb  t1, 13(t0)
    lw  t2, 12(t0)
    CHECK_I(7, t2, 0x11229999)

    li  t1, 0x11223344
    sw  t1, 16(t0)
    li  t1, 0x5566
    sh  t1, 18(t0)
    lw  t2, 16(t0)
    CHECK_I(8, t2, 0x55663344)
    ret

    .section .data
    .align 4
scratch:
    .space 64
