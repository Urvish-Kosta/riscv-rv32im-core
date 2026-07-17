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

    // ---- RV32M (funct3 when opcode==OP_REG and funct7==0000001) ----
    localparam logic [6:0] F7_MULDIV = 7'b0000001;
    typedef enum logic [2:0] {
        MDU_MUL    = 3'b000,
        MDU_MULH   = 3'b001,
        MDU_MULHSU = 3'b010,
        MDU_MULHU  = 3'b011,
        MDU_DIV    = 3'b100,
        MDU_DIVU   = 3'b101,
        MDU_REM    = 3'b110,
        MDU_REMU   = 3'b111
    } mdu_op_e;

    // Behavioural RV32M semantics (one place encodes the spec, including
    // div-by-zero and signed-overflow results). Used combinationally by the
    // single-cycle reference core; the pipeline's iterative mdu.sv must agree
    // with it -- that agreement is exactly what the differential tests check.
    function automatic logic [31:0] mdu_func(input mdu_op_e op,
                                             input logic [31:0] a,
                                             input logic [31:0] b);
        logic signed [63:0] sa, sb, p;
        /* verilator lint_off UNUSED */
        logic        [63:0] ua, ub, up;   // only up[63:32] read (MULHU)
        /* verilator lint_on UNUSED */
        logic signed [31:0] q, r;
        begin
            sa = {{32{a[31]}}, a};  sb = {{32{b[31]}}, b};
            ua = {32'b0, a};        ub = {32'b0, b};
            unique case (op)
                MDU_MUL:    begin p = sa * sb;              mdu_func = p[31:0];  end
                MDU_MULH:   begin p = sa * sb;              mdu_func = p[63:32]; end
                MDU_MULHSU: begin p = sa * $signed(ub);     mdu_func = p[63:32]; end
                MDU_MULHU:  begin up = ua * ub;             mdu_func = up[63:32]; end
                MDU_DIV: begin
                    if (b == 32'd0)                        q = -32'sd1;
                    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) q = 32'sh8000_0000;
                    else                                   q = $signed(a) / $signed(b);
                    mdu_func = q;
                end
                MDU_DIVU:   mdu_func = (b == 32'd0) ? 32'hFFFF_FFFF : (a / b);
                MDU_REM: begin
                    if (b == 32'd0)                        r = $signed(a);
                    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) r = 32'sd0;
                    else                                   r = $signed(a) % $signed(b);
                    mdu_func = r;
                end
                MDU_REMU:   mdu_func = (b == 32'd0) ? a : (a % b);
                default:    mdu_func = 32'd0;
            endcase
        end
    endfunction

    // ---- Minimal Zicsr: read-only counter CSRs ----
    localparam logic [11:0] CSR_CYCLE    = 12'hC00;
    localparam logic [11:0] CSR_INSTRET  = 12'hC02;
    localparam logic [11:0] CSR_CYCLEH   = 12'hC80;
    localparam logic [11:0] CSR_INSTRETH = 12'hC82;

endpackage : riscv_pkg
