#include "test.h"
    .section .text
    .globl test_body
test_body:
    lui   t0, 0x12345
    CHECK_I(1, t0, 0x12345000)
    lui   t0, 0xfffff
    addi  t0, t0, 0x1
    CHECK_I(2, t0, 0xfffff001)
    auipc t1, 0
    auipc t2, 0
    sub   t3, t2, t1        # two auipc one instr apart -> diff = 4
    CHECK_I(3, t3, 4)
    ret
