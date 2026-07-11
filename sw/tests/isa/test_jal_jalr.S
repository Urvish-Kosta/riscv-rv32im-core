#include "test.h"
    .section .text
    .globl test_body
test_body:
    jal  t0, skip           # t0 = address of retpt (jal + 4)
retpt:
    j    _fail              # must be skipped by the jal
skip:
    la   t1, retpt
    CHECK_RR(1, t0, t1)     # JAL link value must equal &retpt

    la   t2, jr_dest
    jalr t3, 0(t2)          # jump to jr_dest, t3 = &jrret (jalr + 4)
jrret:
    j    _fail              # must be skipped by the jalr
jr_dest:
    la   t4, jrret
    CHECK_RR(2, t3, t4)     # JALR link value must equal &jrret
    ret
