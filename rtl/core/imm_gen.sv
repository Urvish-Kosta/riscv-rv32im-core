// -----------------------------------------------------------------------------
// imm_gen.sv  --  sign-extended immediate generation for all RV32I formats
// -----------------------------------------------------------------------------
module imm_gen import riscv_pkg::*; (
    /* verilator lint_off UNUSED */
    input  logic [31:0]     instr,   // opcode bits [6:0] unused here
    /* verilator lint_on UNUSED */
    input  imm_sel_e        sel,
    output logic [XLEN-1:0] imm
);
    logic [XLEN-1:0] i_imm, s_imm, b_imm, u_imm, j_imm;

    assign i_imm = {{20{instr[31]}}, instr[31:20]};
    assign s_imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    assign b_imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    assign u_imm = {instr[31:12], 12'b0};
    assign j_imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    always_comb begin
        unique case (sel)
            IMM_I:   imm = i_imm;
            IMM_S:   imm = s_imm;
            IMM_B:   imm = b_imm;
            IMM_U:   imm = u_imm;
            IMM_J:   imm = j_imm;
            default: imm = '0;
        endcase
    end
endmodule
