// -----------------------------------------------------------------------------
// core_pipe.sv  --  5-stage pipelined RV32I core (milestone M2)
//
// Stages: IF -> ID -> EX -> MEM -> WB, with explicit pipeline registers.
// Branches and jumps are resolved in EX and redirect the PC.
//
// *** NO HAZARD LOGIC YET (by design, for M2). ***
//   - No data forwarding: a dependent instruction must be >= 3 instructions
//     after its producer (2 independent instrs / NOPs between them).
//   - No pipeline stalls.
//   - No branch flush: the two instructions fetched after a control transfer
//     are NOT squashed, so a taken branch/jump has two architectural delay
//     slots. Hazard-free (or delay-slot-padded) code only.
// Correctness on general code arrives at M3 (forwarding + stalls + flush).
//
// The single-cycle core (core_top.sv) remains the functional reference this
// pipeline is checked against on hazard-free programs.
//
// dbg_* outputs mirror core_top's: dmem write port is taken from MEM (for the
// HTIF tohost exit), and the retire trace (pc/instr/rd) is taken from WB.
// -----------------------------------------------------------------------------
module core_pipe import riscv_pkg::*; (
    input  logic            clk,
    input  logic            rst_n,
    output logic [XLEN-1:0] dbg_pc,
    output logic [31:0]     dbg_instr,
    output logic            dbg_reg_we,
    output logic [4:0]      dbg_rd,
    output logic [XLEN-1:0] dbg_wb_data,
    output logic            dbg_dmem_we,
    output logic [XLEN-1:0] dbg_dmem_addr,
    output logic [XLEN-1:0] dbg_dmem_wdata
);
    // WB -> regfile write signals (declared early; driven in WB section).
    logic            wb_reg_write;
    logic [4:0]      wb_rd;
    logic [XLEN-1:0] wb_data;

    // EX -> IF redirect (declared early; driven in EX section).
    logic            redirect;
    logic [XLEN-1:0] redirect_pc;

    // ========================================================= IF
    logic [XLEN-1:0] pc_if, pc_next, pc_plus4_if;
    logic [31:0]     instr_if;

    assign pc_plus4_if = pc_if + 32'd4;
    assign pc_next     = redirect ? redirect_pc : pc_plus4_if;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_if <= RESET_PC;
        else        pc_if <= pc_next;
    end

    imem u_imem (.addr(pc_if), .rdata(instr_if));

    // IF/ID
    logic [XLEN-1:0] ifid_pc;
    logic [31:0]     ifid_instr;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ifid_pc    <= RESET_PC;
            ifid_instr <= 32'h0000_0013;   // NOP bubble
        end else begin
            ifid_pc    <= pc_if;
            ifid_instr <= instr_if;
        end
    end

    // ========================================================= ID
    logic [6:0] id_opcode;
    logic [2:0] id_funct3;
    logic [6:0] id_funct7;
    logic [4:0] id_rs1, id_rs2, id_rd;
    assign id_opcode = ifid_instr[6:0];
    assign id_funct3 = ifid_instr[14:12];
    assign id_funct7 = ifid_instr[31:25];
    assign id_rs1    = ifid_instr[19:15];
    assign id_rs2    = ifid_instr[24:20];
    assign id_rd     = ifid_instr[11:7];

    logic       id_reg_write, id_alu_src_imm, id_alu_a_pc, id_mem_write;
    logic       id_is_branch, id_is_jal, id_is_jalr;
    alu_op_e    id_alu_op;
    imm_sel_e   id_imm_sel;
    wb_sel_e    id_wb_sel;

    control u_ctrl (
        .opcode(id_opcode), .funct3(id_funct3), .funct7(id_funct7),
        .reg_write(id_reg_write), .alu_src_imm(id_alu_src_imm), .alu_a_pc(id_alu_a_pc),
        .alu_op(id_alu_op), .imm_sel(id_imm_sel), .mem_write(id_mem_write),
        .wb_sel(id_wb_sel), .is_branch(id_is_branch), .is_jal(id_is_jal), .is_jalr(id_is_jalr)
    );

    logic [XLEN-1:0] id_rs1d, id_rs2d;
    regfile u_rf (
        .clk(clk), .we(wb_reg_write),
        .rs1_addr(id_rs1), .rs2_addr(id_rs2), .rd_addr(wb_rd),
        .rd_data(wb_data), .rs1_data(id_rs1d), .rs2_data(id_rs2d)
    );

    logic [XLEN-1:0] id_imm;
    imm_gen u_immgen (.instr(ifid_instr), .sel(id_imm_sel), .imm(id_imm));

    // ID/EX
    logic [XLEN-1:0] idex_pc, idex_rs1d, idex_rs2d, idex_imm;
    logic [4:0]      idex_rd;
    logic [2:0]      idex_funct3;
    logic [31:0]     idex_instr;
    logic            idex_reg_write, idex_alu_src_imm, idex_alu_a_pc, idex_mem_write;
    logic            idex_is_branch, idex_is_jal, idex_is_jalr;
    alu_op_e         idex_alu_op;
    wb_sel_e         idex_wb_sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idex_reg_write <= 1'b0; idex_mem_write <= 1'b0;
            idex_is_branch <= 1'b0; idex_is_jal <= 1'b0; idex_is_jalr <= 1'b0;
            idex_alu_src_imm <= 1'b0; idex_alu_a_pc <= 1'b0;
            idex_alu_op <= ALU_ADD; idex_wb_sel <= WB_ALU;
            idex_pc <= RESET_PC; idex_rs1d <= '0; idex_rs2d <= '0; idex_imm <= '0;
            idex_rd <= 5'd0; idex_funct3 <= 3'd0; idex_instr <= 32'h0000_0013;
        end else begin
            idex_reg_write <= id_reg_write; idex_mem_write <= id_mem_write;
            idex_is_branch <= id_is_branch; idex_is_jal <= id_is_jal; idex_is_jalr <= id_is_jalr;
            idex_alu_src_imm <= id_alu_src_imm; idex_alu_a_pc <= id_alu_a_pc;
            idex_alu_op <= id_alu_op; idex_wb_sel <= id_wb_sel;
            idex_pc <= ifid_pc; idex_rs1d <= id_rs1d; idex_rs2d <= id_rs2d; idex_imm <= id_imm;
            idex_rd <= id_rd; idex_funct3 <= id_funct3; idex_instr <= ifid_instr;
        end
    end

    // ========================================================= EX
    logic [XLEN-1:0] ex_alu_a, ex_alu_b, ex_alu_y, ex_pc4;
    assign ex_alu_a = idex_alu_a_pc    ? idex_pc  : idex_rs1d;
    assign ex_alu_b = idex_alu_src_imm ? idex_imm : idex_rs2d;
    assign ex_pc4   = idex_pc + 32'd4;

    alu u_alu (.op(idex_alu_op), .a(ex_alu_a), .b(ex_alu_b), .y(ex_alu_y));

    logic ex_eq, ex_lts, ex_ltu, ex_branch_taken;
    assign ex_eq  = (idex_rs1d == idex_rs2d);
    assign ex_lts = ($signed(idex_rs1d) < $signed(idex_rs2d));
    assign ex_ltu = (idex_rs1d < idex_rs2d);

    always_comb begin
        ex_branch_taken = 1'b0;
        if (idex_is_branch) begin
            unique case (idex_funct3)
                F3_BEQ:  ex_branch_taken = ex_eq;
                F3_BNE:  ex_branch_taken = !ex_eq;
                F3_BLT:  ex_branch_taken = ex_lts;
                F3_BGE:  ex_branch_taken = !ex_lts;
                F3_BLTU: ex_branch_taken = ex_ltu;
                F3_BGEU: ex_branch_taken = !ex_ltu;
                default: ex_branch_taken = 1'b0;
            endcase
        end
    end

    always_comb begin
        redirect    = 1'b0;
        redirect_pc = '0;
        if (idex_is_jal) begin
            redirect = 1'b1; redirect_pc = idex_pc + idex_imm;
        end else if (idex_is_jalr) begin
            redirect = 1'b1; redirect_pc = (idex_rs1d + idex_imm) & ~32'h1;
        end else if (idex_is_branch && ex_branch_taken) begin
            redirect = 1'b1; redirect_pc = idex_pc + idex_imm;
        end
    end

    // EX/MEM
    logic [XLEN-1:0] exmem_alu_y, exmem_rs2d, exmem_pc4, exmem_pc;
    logic [4:0]      exmem_rd;
    logic [2:0]      exmem_funct3;
    logic [31:0]     exmem_instr;
    logic            exmem_reg_write, exmem_mem_write;
    wb_sel_e         exmem_wb_sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exmem_reg_write <= 1'b0; exmem_mem_write <= 1'b0; exmem_wb_sel <= WB_ALU;
            exmem_alu_y <= '0; exmem_rs2d <= '0; exmem_pc4 <= '0; exmem_pc <= RESET_PC;
            exmem_rd <= 5'd0; exmem_funct3 <= 3'd0; exmem_instr <= 32'h0000_0013;
        end else begin
            exmem_reg_write <= idex_reg_write; exmem_mem_write <= idex_mem_write;
            exmem_wb_sel <= idex_wb_sel;
            exmem_alu_y <= ex_alu_y; exmem_rs2d <= idex_rs2d; exmem_pc4 <= ex_pc4;
            exmem_pc <= idex_pc; exmem_rd <= idex_rd; exmem_funct3 <= idex_funct3;
            exmem_instr <= idex_instr;
        end
    end

    // ========================================================= MEM
    logic [XLEN-1:0] mem_rword, mem_load_data, mem_wb_data;
    dmem u_dmem (
        .clk(clk), .addr(exmem_alu_y), .we(exmem_mem_write),
        .size(exmem_funct3[1:0]), .wdata(exmem_rs2d), .rword(mem_rword)
    );

    logic [7:0]  mem_lb;
    logic [15:0] mem_lh;
    assign mem_lb = mem_rword[{exmem_alu_y[1:0], 3'b000} +: 8];
    assign mem_lh = mem_rword[{exmem_alu_y[1], 4'b0000} +: 16];

    always_comb begin
        unique case (exmem_funct3)
            F3_B:    mem_load_data = {{24{mem_lb[7]}},  mem_lb};
            F3_H:    mem_load_data = {{16{mem_lh[15]}}, mem_lh};
            F3_W:    mem_load_data = mem_rword;
            F3_BU:   mem_load_data = {24'b0, mem_lb};
            F3_HU:   mem_load_data = {16'b0, mem_lh};
            default: mem_load_data = mem_rword;
        endcase
    end

    always_comb begin
        unique case (exmem_wb_sel)
            WB_MEM:  mem_wb_data = mem_load_data;
            WB_PC4:  mem_wb_data = exmem_pc4;
            default: mem_wb_data = exmem_alu_y;
        endcase
    end

    // MEM/WB
    logic [XLEN-1:0] memwb_data, memwb_pc;
    logic [4:0]      memwb_rd;
    logic [31:0]     memwb_instr;
    logic            memwb_reg_write;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memwb_reg_write <= 1'b0; memwb_data <= '0; memwb_rd <= 5'd0;
            memwb_pc <= RESET_PC; memwb_instr <= 32'h0000_0013;
        end else begin
            memwb_reg_write <= exmem_reg_write; memwb_data <= mem_wb_data;
            memwb_rd <= exmem_rd; memwb_pc <= exmem_pc; memwb_instr <= exmem_instr;
        end
    end

    // ========================================================= WB
    assign wb_reg_write = memwb_reg_write;
    assign wb_rd        = memwb_rd;
    assign wb_data      = memwb_data;

    // ========================================================= debug/trace
    assign dbg_pc         = memwb_pc;
    assign dbg_instr      = memwb_instr;
    assign dbg_reg_we     = memwb_reg_write && (memwb_rd != 5'd0);
    assign dbg_rd         = memwb_rd;
    assign dbg_wb_data    = memwb_data;
    assign dbg_dmem_we    = exmem_mem_write;
    assign dbg_dmem_addr  = exmem_alu_y;
    assign dbg_dmem_wdata = exmem_rs2d;
endmodule
