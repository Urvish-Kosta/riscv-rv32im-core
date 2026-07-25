// -----------------------------------------------------------------------------
// crt0.S -- C runtime startup for the benchmark kernels.
//
// Sets up the stack, zeroes .bss, calls main(), and reports main()'s return
// value through the HTIF `tohost` protocol: 0 => PASS (tohost 1), non-zero N
// => FAIL with exit code N. Benchmarks are therefore self-checking C programs.
// -----------------------------------------------------------------------------
    .section .text.init
    .globl _start
_start:
    la      sp, _stack_top
    // zero .bss
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:  call    main                    // a0 = result code (0 = pass)
    beqz    a0, 3f
    slli    a0, a0, 1
    ori     a0, a0, 1               // (N<<1)|1 -> exit code N
    j       4f
3:  li      a0, 1                   // tohost 1 -> exit 0
4:  la      t5, tohost
    sw      a0, 0(t5)
5:  j       5b

    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:   .dword 0
    .globl fromhost
fromhost: .dword 0
