// bench_alt.S -- data-dependent alternating branch (T,N,T,N,...) inside a
// counted loop. A 2-bit bimodal counter thrashes on strict alternation; gshare
// keys on history and learns the pattern. Self-checked: exactly half the
// iterations take the inner branch.
    .section .text.init
    .globl _start
_start:
    li   t0, 0          # parity
    li   t1, 0          # i
    li   t2, 2000       # iterations
    li   t3, 0          # count of inner-branch-taken
1:  andi t4, t1, 1
    beq  t4, x0, 2f     # taken on even i, not-taken on odd: alternates
    addi t3, t3, 1      # odd path
2:  addi t1, t1, 1
    bne  t1, t2, 1b
    li   t4, 1000       # odd i in [0,2000) -> 1000
    li   a0, 1
    beq  t3, t4, 3f
    li   a0, 3
3:  la   t5, tohost
    sw   a0, 0(t5)
4:  j 4b
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost: .dword 0
    .globl fromhost
fromhost: .dword 0
