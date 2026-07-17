#include "test.h"
    .section .text
    .globl test_body
test_body:
    # cycle must be strictly increasing, with a sane delta
    rdcycle t0
    rdcycle t1
    li   gp, 1
    bgeu t0, t1, _fail              # t1 > t0 required
    sub  t2, t1, t0
    li   t3, 100
    li   gp, 2
    bgeu t2, t3, _fail              # delta sanity: < 100 cycles
    # instret: two *adjacent* reads may legitimately be equal on a pipelined
    # implementation (flush bubbles retiring between the reads do not count),
    # so put real instructions between the reads -- those must be counted.
    rdinstret t0
    nop
    nop
    nop
    nop
    rdinstret t1
    li   gp, 3
    bgeu t0, t1, _fail              # strictly increasing across 4 real retires
    sub  t2, t1, t0
    li   gp, 4
    bgeu t2, t3, _fail              # and still a sane delta
    # high halves are still zero this early after reset
    rdcycleh t4
    CHECK_I(5, t4, 0)
    rdinstreth t4
    CHECK_I(6, t4, 0)
    # unimplemented CSR reads as zero (documented scope)
    csrrs t4, 0x300, x0             # mstatus -> 0 in this core
    CHECK_I(7, t4, 0)
    ret
