// hazard_showcase.S -- short program that exercises every hazard class in a
// few dozen cycles, so the committed waveform stays small and readable:
//   1. back-to-back RAW  -> EX/MEM forwarding
//   2. distance-2 RAW    -> MEM/WB forwarding
//   3. load-use pair     -> 1-cycle stall + MEM/WB forwarding
//   4. taken branch      -> 2-cycle flush
//   5. multiply          -> ~34-cycle EX stall
    .section .text.init
    .globl _start
_start:
    lui  s2, %hi(scratch)
    addi s2, s2, %lo(scratch)
    li   t0, 5
    addi t1, t0, 3          // (1) back-to-back RAW on t0
    addi t2, t0, 7          // (2) distance-2 RAW on t0
    sw   t1, 0(s2)
    lw   t3, 0(s2)
    addi t4, t3, 1          // (3) load-use: stalls one cycle
    li   t5, 8
    beq  t1, t5, taken      // (4) taken branch -> flush
    j    fail
taken:
    mul  t6, t1, t2         // (5) multi-cycle MDU stall
    li   a1, 96             // 8 * 12
    bne  t6, a1, fail
    li   a0, 1
    j    done
fail:
    li   a0, 3
done:
    la   t5, tohost
    sw   a0, 0(t5)
1:  j 1b
    .section .data
    .align 4
scratch: .space 16
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost: .dword 0
    .globl fromhost
fromhost: .dword 0
