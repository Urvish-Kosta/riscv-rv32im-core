// test_perfcsr.S -- pipeline-only: the non-standard perf counter CSRs are
// readable and behave sanely. (The single-cycle reference reads them as 0 by
// design, so this test runs only on the pipeline.)
#include "test.h"
    .section .text
    .globl test_body
test_body:
    # force a load-use stall, then check the counter is nonzero
    la   t0, scratch
    li   t1, 77
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    addi t2, t2, 1          # load-use pair
    CHECK_I(1, t2, 78)
    csrrs t3, 0xFC0, x0     # load-use stall cycles
    li   gp, 2
    beq  t3, x0, _fail      # must be > 0 by now
    # force an MDU stall, check its counter moves
    csrrs t3, 0xFC1, x0
    li   t1, 6
    li   t2, 7
    mul  t4, t1, t2
    CHECK_I(3, t4, 42)
    csrrs t5, 0xFC1, x0
    li   gp, 4
    bgeu t3, t5, _fail      # strictly increased across the mul
    # branch counters: the CHECKs above executed conditional branches
    csrrs t3, 0xFC3, x0     # cond branches resolved
    li   gp, 5
    beq  t3, x0, _fail
    ret
    .section .data
    .align 4
scratch: .space 8
