// -----------------------------------------------------------------------------
// core_top.sv  --  single-cycle RV32I datapath (milestone M1)
//
// One instruction per clock. No pipeline, no hazards. This is the *functional
// reference* the pipelined core (M2+) is checked against.
//
// Debug/trace outputs (dbg_*) are for the simulation harness only: they expose
// the retiring instruction and the data-memory write port so the testbench can
// implement the HTIF `tohost` exit protocol and emit a retire trace. They cost
// nothing functionally and would be stripped for synthesis.
// -----------------------------------------------------------------------------
module core_top import riscv_pkg::*; (
    input  logic            clk,
    input  logic            rst_n,
    // --- debug / trace (harness only) ---
    output logic [XLEN-1:0] dbg_pc,
    output logic [31:0]     dbg_instr,
    output logic            dbg_reg_we,
    output logic [4:0]      dbg_rd,
    output logic [XLEN-1:0] dbg_wb_data,
    output logic            dbg_dmem_we,
    output logic [XLEN-1:0] dbg_dmem_addr,
    output logic [XLEN-1:0] dbg_dmem_wdata
);
    // ---------------------------------------------------------------- fetch
    logic [XLEN-1:0] pc, next_pc;
    logic [31:0]     instr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc <= RESET_PC;
        else        pc <= next_pc;
    end

    imem u_imem (.addr(pc), .rdata(instr));

    // --------------------------------------------------------------- decode
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [4:0] rs1, rs2, rd;
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];

    logic       reg_write, alu_src_imm, alu_a_pc, mem_write;
    logic       is_branch, is_jal, is_jalr, is_mdu, is_csr;
    alu_op_e    alu_op;
    imm_sel_e   imm_sel;
    wb_sel_e    wb_sel;

    control u_ctrl (
        .opcode, .funct3, .funct7,
        .reg_write, .alu_src_imm, .alu_a_pc, .alu_op, .imm_sel,
        .mem_write, .wb_sel, .is_branch, .is_jal, .is_jalr, .is_mdu, .is_csr
    );

    // ------------------------------------------------------------ registers
    logic [XLEN-1:0] rs1_data, rs2_data, wb_data;
    regfile u_rf (
        .clk, .we(reg_write),
        .rs1_addr(rs1), .rs2_addr(rs2), .rd_addr(rd),
        .rd_data(wb_data), .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    // ------------------------------------------------------------ immediate
    logic [XLEN-1:0] imm;
    imm_gen u_immgen (.instr(instr), .sel(imm_sel), .imm(imm));

    // ------------------------------------------------------------------ ALU
    logic [XLEN-1:0] alu_a, alu_b, alu_y, alu_y_raw;
    assign alu_a = alu_a_pc    ? pc  : rs1_data;
    assign alu_b = alu_src_imm ? imm : rs2_data;
    alu u_alu (.op(alu_op), .a(alu_a), .b(alu_b), .y(alu_y_raw));

    // RV32M: the reference core computes M results *behaviourally* in one
    // cycle via riscv_pkg::mdu_func -- the executable spec the pipeline's
    // iterative mdu.sv is checked against. Zicsr: counter CSR reads.
    logic [XLEN-1:0] csr_rdata;
    assign alu_y = is_mdu ? mdu_func(mdu_op_e'(funct3), rs1_data, rs2_data)
                 : is_csr ? csr_rdata
                 :          alu_y_raw;

    // ---------------------------------------------------------- branch unit
    logic eq, lt_s, lt_u, branch_taken;
    assign eq   = (rs1_data == rs2_data);
    assign lt_s = ($signed(rs1_data) < $signed(rs2_data));
    assign lt_u = (rs1_data < rs2_data);

    always_comb begin
        branch_taken = 1'b0;
        if (is_branch) begin
            unique case (funct3)
                F3_BEQ:  branch_taken = eq;
                F3_BNE:  branch_taken = !eq;
                F3_BLT:  branch_taken = lt_s;
                F3_BGE:  branch_taken = !lt_s;
                F3_BLTU: branch_taken = lt_u;
                F3_BGEU: branch_taken = !lt_u;
                default: branch_taken = 1'b0;
            endcase
        end
    end

    // -------------------------------------------------------------- next PC
    logic [XLEN-1:0] pc_plus4;
    assign pc_plus4 = pc + 32'd4;

    always_comb begin
        if      (is_jal)               next_pc = pc + imm;            // J-imm
        else if (is_jalr)              next_pc = (rs1_data + imm) & ~32'h1;
        else if (branch_taken)         next_pc = pc + imm;            // B-imm
        else                           next_pc = pc_plus4;
    end

    // ------------------------------------------------------- data memory
    logic [XLEN-1:0] dmem_rword, load_data;
    dmem u_dmem (
        .clk, .addr(alu_y), .we(mem_write), .size(funct3[1:0]),
        .wdata(rs2_data), .rword(dmem_rword)
    );

    // load extraction / extension
    logic [7:0]  lb_byte;
    logic [15:0] lh_half;
    assign lb_byte = dmem_rword[{alu_y[1:0], 3'b000} +: 8];
    assign lh_half = dmem_rword[{alu_y[1], 4'b0000} +: 16];

    always_comb begin
        unique case (funct3)
            F3_B:    load_data = {{24{lb_byte[7]}},  lb_byte};
            F3_H:    load_data = {{16{lh_half[15]}}, lh_half};
            F3_W:    load_data = dmem_rword;
            F3_BU:   load_data = {24'b0, lb_byte};
            F3_HU:   load_data = {16'b0, lh_half};
            default: load_data = dmem_rword;
        endcase
    end

    // ------------------------------------------------------------ writeback
    always_comb begin
        unique case (wb_sel)
            WB_MEM:  wb_data = load_data;
            WB_PC4:  wb_data = pc_plus4;
            default: wb_data = alu_y;
        endcase
    end

    // ------------------------------------------------------ counter CSRs
    // Single-cycle core: exactly one instruction retires per cycle, so
    // cycle == instret by construction.
    logic [63:0] csr_cycle;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) csr_cycle <= 64'd0;
        else        csr_cycle <= csr_cycle + 64'd1;
    end
    always_comb begin
        unique case (instr[31:20])
            CSR_CYCLE,  CSR_INSTRET:  csr_rdata = csr_cycle[31:0];
            CSR_CYCLEH, CSR_INSTRETH: csr_rdata = csr_cycle[63:32];
            default:                  csr_rdata = 32'd0;
        endcase
    end

    // ---------------------------------------------------------------- debug
    assign dbg_pc         = pc;
    assign dbg_instr      = instr;
    assign dbg_reg_we     = reg_write && (rd != 5'd0);
    assign dbg_rd         = rd;
    assign dbg_wb_data    = wb_data;
    assign dbg_dmem_we    = mem_write;
    assign dbg_dmem_addr  = alu_y;
    assign dbg_dmem_wdata = rs2_data;
endmodule
