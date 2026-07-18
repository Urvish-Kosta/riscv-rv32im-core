// bench_mixed.S -- nested loops with loads/stores and mul/div in the body:
// exercises load-use stalls, MDU stalls, and both branch levels together.
// Self-checked against a hand-derived accumulator value.
//
// outer j = 1..8, inner i = 1..16:
//   mem[i%4] = i*j ; acc += mem[i%4] / j  == acc += i  (i*j/j == i exactly)
// => acc = 8 * sum(1..16) = 8*136 = 1088
    .section .text.init
    .globl _start
_start:
    lui  s2, %hi(scratch)
    addi s2, s2, %lo(scratch)
    li   s0, 0          # acc
    li   t6, 1          # j
1:  li   t1, 1          # i
2:  mul  t2, t1, t6     # i*j
    andi t3, t1, 3
    slli t3, t3, 2
    add  t3, t3, s2
    sw   t2, 0(t3)
    lw   t4, 0(t3)      # load-use follows
    div  t5, t4, t6     # (i*j)/j == i
    add  s0, s0, t5
    addi t1, t1, 1
    li   t2, 17
    bne  t1, t2, 2b
    addi t6, t6, 1
    li   t2, 9
    bne  t6, t2, 1b
    li   t3, 1088
    li   a0, 1
    beq  s0, t3, 3f
    li   a0, 3
3:  la   t5, tohost
    sw   a0, 0(t5)
4:  j 4b
    .section .data
    .align 4
scratch: .space 16
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost: .dword 0
    .globl fromhost
fromhost: .dword 0
