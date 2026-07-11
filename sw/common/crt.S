# -----------------------------------------------------------------------------
# crt.S -- minimal startup + HTIF pass/fail reporting for self-checking tests
#
# Layout: _start (at RESET_PC) zeroes the test-number tracker (gp), calls the
# test's `test_body`, and on normal return reports PASS. Any check that fails
# branches to _fail, which reports the failing test number as the exit code.
# Reserved registers (tests must not clobber): x1/ra, x3/gp, t5, t6, a0.
# -----------------------------------------------------------------------------
    .section .text.init
    .globl _start
_start:
    li      gp, 0
    call    test_body           # returns here on success
_pass:
    li      a0, 1               # HTIF: value 1 -> exit code 0 (PASS)
    j       _halt
    .globl _fail
_fail:                          # gp holds the failing test number
    slli    a0, gp, 1
    ori     a0, a0, 1           # (num << 1) | 1 -> exit code = num (FAIL)
    .globl _halt
_halt:
    la      t5, tohost
    sw      a0, 0(t5)           # store to tohost ends the simulation
1:  j       1b

    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:   .dword 0
    .globl fromhost
fromhost: .dword 0
