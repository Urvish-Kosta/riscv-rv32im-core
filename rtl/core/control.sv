// -----------------------------------------------------------------------------
// control.sv  --  main + ALU decode for the single-cycle RV32I core
// Produces every datapath control signal from opcode/funct3/funct7.
// Unknown/unsupported opcodes (FENCE, SYSTEM, illegal) decode to a NOP:
// no register write, no memory access, no control transfer.
// -----------------------------------------------------------------------------
module control import riscv_pkg::*; (
    input  logic [6:0]  opcode,
    input  logic [2:0]  funct3,
    input  logic [6:0]  funct7,
    output logic        reg_write,
    output logic        alu_src_imm,  // 1: ALU B = immediate, 0: ALU B = rs2
    output logic        alu_a_pc,     // 1: ALU A = PC (AUIPC), 0: ALU A = rs1
    output alu_op_e     alu_op,
    output imm_sel_e    imm_sel,
    output logic        mem_write,
    output wb_sel_e     wb_sel,
    output logic        is_branch,
    output logic        is_jal,
    output logic        is_jalr,
    output logic        is_mdu,      // RV32M op (funct7 == 0000001, OP_REG)
    output logic        is_csr       // Zicsr read (counters; writes ignored)
);
    // ALU op for OP_REG / OP_IMM from funct3 (+ funct7[5] for SUB/SRA).
    function automatic alu_op_e arith_alu_op(input logic is_reg);
        unique case (funct3)
            3'b000: arith_alu_op = (is_reg && funct7[5]) ? ALU_SUB : ALU_ADD; // ADD/SUB/ADDI
            3'b001: arith_alu_op = ALU_SLL;
            3'b010: arith_alu_op = ALU_SLT;
            3'b011: arith_alu_op = ALU_SLTU;
            3'b100: arith_alu_op = ALU_XOR;
            3'b101: arith_alu_op = funct7[5] ? ALU_SRA : ALU_SRL;            // SRA/SRL(+I)
            3'b110: arith_alu_op = ALU_OR;
            3'b111: arith_alu_op = ALU_AND;
            default: arith_alu_op = ALU_ADD;
        endcase
    endfunction

    always_comb begin
        // Safe NOP defaults.
        reg_write   = 1'b0;
        alu_src_imm = 1'b0;
        alu_a_pc    = 1'b0;
        alu_op      = ALU_ADD;
        imm_sel     = IMM_NONE;
        mem_write   = 1'b0;
        wb_sel      = WB_ALU;
        is_branch   = 1'b0;
        is_jal      = 1'b0;
        is_jalr     = 1'b0;
        is_mdu      = 1'b0;
        is_csr      = 1'b0;

        unique case (opcode)
            OP_REG: begin
                reg_write = 1'b1;
                if (funct7 == F7_MULDIV) is_mdu = 1'b1;   // funct3 selects the M op
                else                     alu_op = arith_alu_op(1'b1);
            end
            OP_IMM: begin
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                imm_sel     = IMM_I;
                alu_op      = arith_alu_op(1'b0);
            end
            OP_LOAD: begin
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                imm_sel     = IMM_I;
                alu_op      = ALU_ADD;
                wb_sel      = WB_MEM;
            end
            OP_STORE: begin
                alu_src_imm = 1'b1;
                imm_sel     = IMM_S;
                alu_op      = ALU_ADD;
                mem_write   = 1'b1;
            end
            OP_BRANCH: begin
                imm_sel   = IMM_B;
                is_branch = 1'b1;
            end
            OP_LUI: begin
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                imm_sel     = IMM_U;
                alu_op      = ALU_PASS_B;
            end
            OP_AUIPC: begin
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                alu_a_pc    = 1'b1;
                imm_sel     = IMM_U;
                alu_op      = ALU_ADD;
            end
            OP_JAL: begin
                reg_write = 1'b1;
                imm_sel   = IMM_J;
                wb_sel    = WB_PC4;
                is_jal    = 1'b1;
            end
            OP_JALR: begin
                reg_write = 1'b1;
                imm_sel   = IMM_I;
                wb_sel    = WB_PC4;
                is_jalr   = 1'b1;
            end
            OP_FENCE: begin
                // NOP: single hart, no caches -- ordering is trivially satisfied.
            end
            OP_SYSTEM: begin
                if (funct3 != 3'b000) begin
                    // CSRRW/CSRRS/CSRRC (+ immediate forms): implemented as
                    // CSR *reads* of the counter CSRs (cycle/instret/+h).
                    // Write side-effects are ignored -- all implemented CSRs
                    // are read-only counters; unknown CSRs read as 0.
                    is_csr    = 1'b1;
                    reg_write = 1'b1;
                end
                // funct3 == 000 (ECALL/EBREAK): NOP at this milestone.
            end
            default: begin
                // Illegal / unimplemented -> NOP.
            end
        endcase
    end
endmodule
