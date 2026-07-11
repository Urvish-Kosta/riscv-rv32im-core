// -----------------------------------------------------------------------------
// riscv_pkg.sv  --  shared parameters, encodings, and control types (RV32I / M1)
// -----------------------------------------------------------------------------
package riscv_pkg;

    parameter int unsigned      XLEN     = 32;
    parameter logic [XLEN-1:0]  RESET_PC = 32'h8000_0000;

    // ---- Opcodes (instr[6:0]) ----
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_IMM    = 7'b0010011;
    localparam logic [6:0] OP_REG    = 7'b0110011;
    localparam logic [6:0] OP_FENCE  = 7'b0001111;
    localparam logic [6:0] OP_SYSTEM = 7'b1110011;

    // ---- funct3 for loads/stores ----
    localparam logic [2:0] F3_B  = 3'b000, F3_H  = 3'b001, F3_W  = 3'b010,
                           F3_BU = 3'b100, F3_HU = 3'b101;

    // ---- funct3 for branches ----
    localparam logic [2:0] F3_BEQ = 3'b000, F3_BNE = 3'b001,
                           F3_BLT = 3'b100, F3_BGE = 3'b101,
                           F3_BLTU= 3'b110, F3_BGEU= 3'b111;

    // ---- ALU operations ----
    typedef enum logic [3:0] {
        ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
        ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND,
        ALU_PASS_B                              // pass operand B (LUI)
    } alu_op_e;

    // ---- Immediate format select ----
    typedef enum logic [2:0] { IMM_I, IMM_S, IMM_B, IMM_U, IMM_J, IMM_NONE } imm_sel_e;

    // ---- Writeback source ----
    typedef enum logic [1:0] { WB_ALU, WB_MEM, WB_PC4 } wb_sel_e;

endpackage : riscv_pkg
