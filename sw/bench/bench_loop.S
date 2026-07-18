// bench_loop.S -- tight counted loop: sum 1..1000, self-checked (500500).
// Backward branch taken 999x then falls through: highly predictable; measures
// the taken-branch penalty that prediction removes.
    .section .text.init
    .globl _start
_start:
    li   t0, 0          # sum
    li   t1, 1          # i
    li   t2, 1001
1:  add  t0, t0, t1
    addi t1, t1, 1
    bne  t1, t2, 1b
    li   t3, 500500
    li   a0, 1
    beq  t0, t3, 2f
    li   a0, 3          # (1<<1)|1 -> exit 1 = FAIL
2:  la   t5, tohost
    sw   a0, 0(t5)
3:  j 3b
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost: .dword 0
    .globl fromhost
fromhost: .dword 0
