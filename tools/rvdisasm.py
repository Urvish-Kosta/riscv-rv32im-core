#!/usr/bin/env python3
"""rvdisasm.py -- minimal RV32IM + Zicsr disassembler for the trace tools.

Not a general-purpose disassembler: it covers exactly the instruction set the
core implements, which is what the retire traces contain. Also exposes the
field accessors (`rs1`, `rs2`, `rd`, `opcode`) the comparison tool needs to
reason about data flow.
"""

REG = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
]

BRANCH = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}
LOAD = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
STORE = {0: "sb", 1: "sh", 2: "sw"}
ALU = {0: "add", 1: "sll", 2: "slt", 3: "sltu", 4: "xor", 5: "srl", 6: "or", 7: "and"}
ALUI = {0: "addi", 1: "slli", 2: "slti", 3: "sltiu", 4: "xori", 5: "srli", 6: "ori", 7: "andi"}
MOP = {0: "mul", 1: "mulh", 2: "mulhsu", 3: "mulhu", 4: "div", 5: "divu", 6: "rem", 7: "remu"}
CSROP = {1: "csrrw", 2: "csrrs", 3: "csrrc", 5: "csrrwi", 6: "csrrsi", 7: "csrrci"}
CSR_NAMES = {
    0xC00: "cycle", 0xC02: "instret", 0xC80: "cycleh", 0xC82: "instreth",
    0xFC0: "perf_loaduse", 0xFC1: "perf_mdu", 0xFC2: "perf_redirect",
    0xFC3: "perf_br", 0xFC4: "perf_br_tk", 0xFC5: "perf_br_mp",
}


def opcode(w): return w & 0x7F
def rd(w):     return (w >> 7) & 0x1F
def funct3(w): return (w >> 12) & 0x7
def rs1(w):    return (w >> 15) & 0x1F
def rs2(w):    return (w >> 20) & 0x1F
def funct7(w): return (w >> 25) & 0x7F
def csr(w):    return (w >> 20) & 0xFFF


def _sx(v, bits):
    """Sign-extend a `bits`-wide value."""
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def imm_i(w): return _sx((w >> 20) & 0xFFF, 12)
def imm_s(w): return _sx((((w >> 25) & 0x7F) << 5) | ((w >> 7) & 0x1F), 12)


def imm_b(w):
    v = (((w >> 31) & 1) << 12) | (((w >> 7) & 1) << 11) | \
        (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1)
    return _sx(v, 13)


def imm_j(w):
    v = (((w >> 31) & 1) << 20) | (((w >> 12) & 0xFF) << 12) | \
        (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1)
    return _sx(v, 21)


def is_csr_read(w):
    """True for a CSR access (SYSTEM opcode with a non-zero funct3)."""
    return opcode(w) == 0x73 and funct3(w) != 0


def source_regs(w):
    """Integer source registers actually read by this instruction."""
    op = opcode(w)
    if op in (0x33,):                      # R-type (incl. M)
        return {rs1(w), rs2(w)}
    if op in (0x13, 0x03, 0x67):           # I-type, loads, JALR
        return {rs1(w)}
    if op in (0x23, 0x63):                 # stores, branches
        return {rs1(w), rs2(w)}
    if op == 0x73 and funct3(w) in (1, 2, 3):   # csrrw/s/c read a register
        return {rs1(w)}
    return set()                            # LUI/AUIPC/JAL/csr*i: none


def disasm(word, pc=None):
    """Return an assembly string for a 32-bit instruction word."""
    w = word & 0xFFFFFFFF
    op, f3, f7 = opcode(w), funct3(w), funct7(w)
    r = lambda i: REG[i]

    if w == 0x00000013:
        return "nop"
    if op == 0x37:
        return f"lui {r(rd(w))}, 0x{(w >> 12) & 0xFFFFF:x}"
    if op == 0x17:
        return f"auipc {r(rd(w))}, 0x{(w >> 12) & 0xFFFFF:x}"
    if op == 0x6F:
        t = f"0x{pc + imm_j(w):08x}" if pc is not None else f"{imm_j(w):+d}"
        return f"jal {r(rd(w))}, {t}"
    if op == 0x67:
        return f"jalr {r(rd(w))}, {imm_i(w)}({r(rs1(w))})"
    if op == 0x63:
        t = f"0x{pc + imm_b(w):08x}" if pc is not None else f"{imm_b(w):+d}"
        return f"{BRANCH.get(f3, '?br')} {r(rs1(w))}, {r(rs2(w))}, {t}"
    if op == 0x03:
        return f"{LOAD.get(f3, '?ld')} {r(rd(w))}, {imm_i(w)}({r(rs1(w))})"
    if op == 0x23:
        return f"{STORE.get(f3, '?st')} {r(rs2(w))}, {imm_s(w)}({r(rs1(w))})"
    if op == 0x13:
        if f3 in (1, 5):
            m = "srai" if (f3 == 5 and (f7 & 0x20)) else ALUI[f3]
            return f"{m} {r(rd(w))}, {r(rs1(w))}, {rs2(w)}"
        return f"{ALUI.get(f3, '?opi')} {r(rd(w))}, {r(rs1(w))}, {imm_i(w)}"
    if op == 0x33:
        if f7 == 0x01:
            return f"{MOP.get(f3, '?m')} {r(rd(w))}, {r(rs1(w))}, {r(rs2(w))}"
        m = ALU.get(f3, "?op")
        if f7 & 0x20:
            m = "sub" if f3 == 0 else ("sra" if f3 == 5 else m)
        return f"{m} {r(rd(w))}, {r(rs1(w))}, {r(rs2(w))}"
    if op == 0x0F:
        return "fence"
    if op == 0x73:
        if f3 == 0:
            return "ecall" if imm_i(w) == 0 else "ebreak"
        name = CSR_NAMES.get(csr(w), f"0x{csr(w):03x}")
        m = CSROP.get(f3, "?csr")
        src = f"{rs1(w)}" if f3 >= 5 else r(rs1(w))
        return f"{m} {r(rd(w))}, {name}, {src}"
    return f".word 0x{w:08x}"
