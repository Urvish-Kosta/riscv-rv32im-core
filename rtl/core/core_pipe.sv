// -----------------------------------------------------------------------------
// core_pipe.sv  --  5-stage pipelined RV32I core (milestone M3: full hazard logic)
//
// Stages: IF -> ID -> EX -> MEM -> WB, with explicit pipeline registers.
// Branches and jumps are resolved in EX and redirect the PC.
//
// Hazard handling (new at M3):
//   - Data forwarding into EX from EX/MEM (ALU result / pc+4, never load
//     data) and from MEM/WB (final writeback value).
//   - WB -> ID bypass: the shared regfile is sync-write/comb-read, so a value
//     being written back is bypassed to a reader in ID the same cycle. (The
//     regfile itself is not write-first: in the single-cycle core that would
//     form a combinational loop through its own writeback path.)
//   - Load-use stall: a load in EX with a dependent consumer in ID stalls
//     IF/ID for one cycle and inserts one bubble into EX; MEM/WB forwarding
//     then supplies the loaded value.
//   - Control flush: a redirect from EX (taken branch, JAL, JALR) squashes
//     the two younger instructions in IF/ID and ID/EX.
// The core is therefore correct on arbitrary RV32I code (no NOP padding, no
// delay slots).
//
// The single-cycle core (core_top.sv) remains the functional reference this
// pipeline is verified against differentially.
//
// dbg_* outputs mirror core_top's: dmem write port is taken from MEM (for the
// HTIF tohost exit), and the retire trace (pc/instr/rd) is taken from WB.
// -----------------------------------------------------------------------------
module core_pipe import riscv_pkg::*; (
    input  logic            clk,
    input  logic            rst_n,
    input  logic [1:0]      cfg_bp_mode,   // 0 off, 1 bimodal, 2 gshare
    output logic            dbg_retire,    // valid instruction retiring (WB)
    output logic [31:0]     dbg_n_loaduse, // perf: load-use stall cycles
    output logic [31:0]     dbg_n_mdu,     // perf: MDU stall cycles
    output logic [31:0]     dbg_n_redirect,// perf: control redirects (all)
    output logic [31:0]     dbg_n_br,      // perf: cond branches resolved
    output logic [31:0]     dbg_n_br_tk,   // perf: cond branches taken
    output logic [31:0]     dbg_n_br_mp,   // perf: cond branch mispredicts
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

    // Load-use stall (declared early; driven in the hazard section).
    logic            stall;

    // ========================================================= IF
    logic [XLEN-1:0] pc_if, pc_plus4_if, pred_npc_if;
    logic [31:0]     instr_if;
    logic            bp_pred_taken;
    logic [XLEN-1:0] bp_pred_target;
    logic [7:0]      bp_pred_pidx;

    assign pc_plus4_if = pc_if + 32'd4;
    // Predicted next PC for the instruction being fetched. With the predictor
    // off this is always pc+4, which reproduces the M3/M4 static-not-taken
    // behaviour exactly.
    assign pred_npc_if = bp_pred_taken ? bp_pred_target : pc_plus4_if;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)        pc_if <= RESET_PC;
        else if (redirect) pc_if <= redirect_pc;  // mispredict recovery wins
        else if (!stall)   pc_if <= pred_npc_if;  // follow the prediction
        // else: hold (load-use or MDU stall; redirect is suppressed during an
        // MDU stall and cannot occur for the load itself thanks to the
        // full-tag BTB, but the priority above is written to be safe anyway)
    end

    imem u_imem (.addr(pc_if), .rdata(instr_if));

    // IF/ID
    logic [XLEN-1:0] ifid_pc, ifid_pred_npc;
    logic [7:0]      ifid_bp_pidx;
    logic [31:0]     ifid_instr;
    logic            ifid_valid;   // real instruction (not a bubble): instret
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ifid_pc    <= RESET_PC;
            ifid_instr <= 32'h0000_0013;   // NOP bubble
            ifid_valid <= 1'b0;
        end else if (redirect) begin       // flush the wrong-path fetch
            ifid_pc    <= RESET_PC;
            ifid_instr <= 32'h0000_0013;
            ifid_valid <= 1'b0;
        end else if (!stall) begin         // hold on a stall
            ifid_pc       <= pc_if;
            ifid_instr    <= instr_if;
            ifid_valid    <= 1'b1;
            ifid_pred_npc <= pred_npc_if;
            ifid_bp_pidx  <= bp_pred_pidx;
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
    logic       id_is_branch, id_is_jal, id_is_jalr, id_is_mdu, id_is_csr;
    alu_op_e    id_alu_op;
    imm_sel_e   id_imm_sel;
    wb_sel_e    id_wb_sel;

    control u_ctrl (
        .opcode(id_opcode), .funct3(id_funct3), .funct7(id_funct7),
        .reg_write(id_reg_write), .alu_src_imm(id_alu_src_imm), .alu_a_pc(id_alu_a_pc),
        .alu_op(id_alu_op), .imm_sel(id_imm_sel), .mem_write(id_mem_write),
        .wb_sel(id_wb_sel), .is_branch(id_is_branch), .is_jal(id_is_jal), .is_jalr(id_is_jalr),
        .is_mdu(id_is_mdu), .is_csr(id_is_csr)
    );

    logic [XLEN-1:0] id_rs1d_raw, id_rs2d_raw, id_rs1d, id_rs2d;
    regfile u_rf (
        .clk(clk), .we(wb_reg_write),
        .rs1_addr(id_rs1), .rs2_addr(id_rs2), .rd_addr(wb_rd),
        .rd_data(wb_data), .rs1_data(id_rs1d_raw), .rs2_data(id_rs2d_raw)
    );

    // WB -> ID bypass: the regfile write lands on this posedge, so a reader in
    // ID would otherwise see the stale value (sync write, comb read).
    assign id_rs1d = (wb_reg_write && wb_rd != 5'd0 && wb_rd == id_rs1) ? wb_data : id_rs1d_raw;
    assign id_rs2d = (wb_reg_write && wb_rd != 5'd0 && wb_rd == id_rs2) ? wb_data : id_rs2d_raw;

    logic [XLEN-1:0] id_imm;
    imm_gen u_immgen (.instr(ifid_instr), .sel(id_imm_sel), .imm(id_imm));

    // ID/EX
    logic [XLEN-1:0] idex_pc, idex_rs1d, idex_rs2d, idex_imm;
    logic [4:0]      idex_rs1, idex_rs2;
    logic [4:0]      idex_rd;
    logic            idex_valid, idex_is_mdu, idex_is_csr;
    logic [11:0]     idex_csr_addr;
    logic [XLEN-1:0] idex_pred_npc;
    logic [7:0]      idex_bp_pidx;
    logic [2:0]      idex_funct3;
    logic [31:0]     idex_instr;
    logic            idex_reg_write, idex_alu_src_imm, idex_alu_a_pc, idex_mem_write;
    logic            idex_is_branch, idex_is_jal, idex_is_jalr;
    alu_op_e         idex_alu_op;
    wb_sel_e         idex_wb_sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || redirect || load_use_stall) begin
            // Bubble: on reset, on a control flush (squash the wrong-path
            // instruction in ID), or on a load-use stall (insert the bubble
            // that separates load and consumer).
            // NOTE: an MDU stall does NOT bubble ID/EX -- the M instruction
            // must stay in EX; that case holds the register instead (below).
            idex_reg_write <= 1'b0; idex_mem_write <= 1'b0;
            idex_is_branch <= 1'b0; idex_is_jal <= 1'b0; idex_is_jalr <= 1'b0;
            idex_alu_src_imm <= 1'b0; idex_alu_a_pc <= 1'b0;
            idex_alu_op <= ALU_ADD; idex_wb_sel <= WB_ALU;
            idex_pc <= RESET_PC; idex_rs1d <= '0; idex_rs2d <= '0; idex_imm <= '0;
            idex_rs1 <= 5'd0; idex_rs2 <= 5'd0;
            idex_rd <= 5'd0; idex_funct3 <= 3'd0; idex_instr <= 32'h0000_0013;
            idex_valid <= 1'b0; idex_is_mdu <= 1'b0; idex_is_csr <= 1'b0;
            idex_csr_addr <= 12'd0; idex_pred_npc <= RESET_PC;
        end else if (!mdu_stall) begin
            idex_reg_write <= id_reg_write; idex_mem_write <= id_mem_write;
            idex_is_branch <= id_is_branch; idex_is_jal <= id_is_jal; idex_is_jalr <= id_is_jalr;
            idex_alu_src_imm <= id_alu_src_imm; idex_alu_a_pc <= id_alu_a_pc;
            idex_alu_op <= id_alu_op; idex_wb_sel <= id_wb_sel;
            idex_pc <= ifid_pc; idex_rs1d <= id_rs1d; idex_rs2d <= id_rs2d; idex_imm <= id_imm;
            idex_rs1 <= id_rs1; idex_rs2 <= id_rs2;
            idex_rd <= id_rd; idex_funct3 <= id_funct3; idex_instr <= ifid_instr;
            idex_valid <= ifid_valid; idex_is_mdu <= id_is_mdu; idex_is_csr <= id_is_csr;
            idex_csr_addr <= ifid_instr[31:20];
            idex_pred_npc <= ifid_pred_npc;
            idex_bp_pidx  <= ifid_bp_pidx;
        end
    end

    // ========================================================= EX
    // ---- forwarding (M3) ----
    // EX/MEM forwards its ALU result or pc+4 (never load data: a dependent
    // consumer of a load is separated by the load-use stall, after which the
    // value arrives via the MEM/WB path). MEM/WB forwards the final writeback
    // value, which covers ALU results, pc+4 and load data alike.
    // Priority: EX/MEM (younger) over MEM/WB (older).
    logic [XLEN-1:0] exmem_fwd_val;   // defined after EX/MEM regs; forward decl
    logic            exmem_fwd_ok;
    logic [XLEN-1:0] ex_rs1_fwd, ex_rs2_fwd;

    always_comb begin
        ex_rs1_fwd = idex_rs1d;
        if (idex_rs1 != 5'd0) begin
            if (exmem_fwd_ok && exmem_rd == idex_rs1)           ex_rs1_fwd = exmem_fwd_val;
            else if (memwb_reg_write && memwb_rd == idex_rs1)   ex_rs1_fwd = memwb_data;
        end
        ex_rs2_fwd = idex_rs2d;
        if (idex_rs2 != 5'd0) begin
            if (exmem_fwd_ok && exmem_rd == idex_rs2)           ex_rs2_fwd = exmem_fwd_val;
            else if (memwb_reg_write && memwb_rd == idex_rs2)   ex_rs2_fwd = memwb_data;
        end
    end

    logic [XLEN-1:0] ex_alu_a, ex_alu_b, ex_alu_y, ex_pc4, ex_result;
    assign ex_alu_a = idex_alu_a_pc    ? idex_pc  : ex_rs1_fwd;
    assign ex_alu_b = idex_alu_src_imm ? idex_imm : ex_rs2_fwd;
    assign ex_pc4   = idex_pc + 32'd4;

    alu u_alu (.op(idex_alu_op), .a(ex_alu_a), .b(ex_alu_b), .y(ex_alu_y));

    // ---- RV32M: iterative unit, stalls the instruction in EX until done ----
    logic        mdu_busy, mdu_done, mdu_start;
    logic [31:0] mdu_result;
    assign mdu_start = idex_is_mdu && !mdu_busy && !mdu_done;
    mdu u_mdu (
        .clk, .rst_n, .start(mdu_start), .op(mdu_op_e'(idex_funct3)),
        .a(ex_rs1_fwd), .b(ex_rs2_fwd),
        .busy(mdu_busy), .done(mdu_done), .result(mdu_result)
    );
    // The M instruction is held in EX (upstream stalled, bubbles injected into
    // EX/MEM) until the unit reports done.
    logic mdu_stall;
    assign mdu_stall = idex_is_mdu && !mdu_done;

    // ---- Zicsr: counter CSR read in EX ----
    logic [XLEN-1:0] csr_rdata;   // driven in the CSR section below

    // EX result: ALU, M unit, or CSR read.
    assign ex_result = idex_is_mdu ? mdu_result
                     : idex_is_csr ? csr_rdata
                     :               ex_alu_y;

    logic ex_eq, ex_lts, ex_ltu, ex_branch_taken;
    assign ex_eq  = (ex_rs1_fwd == ex_rs2_fwd);
    assign ex_lts = ($signed(ex_rs1_fwd) < $signed(ex_rs2_fwd));
    assign ex_ltu = (ex_rs1_fwd < ex_rs2_fwd);

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

    // Actual next PC of the instruction in EX -- for *every* instruction.
    logic [XLEN-1:0] ex_actual_npc, ex_taken_target;
    always_comb begin
        ex_taken_target = idex_pc + idex_imm;                    // JAL / branch
        if (idex_is_jalr) ex_taken_target = (ex_rs1_fwd + idex_imm) & ~32'h1;
        if (idex_is_jal || idex_is_jalr ||
            (idex_is_branch && ex_branch_taken))
            ex_actual_npc = ex_taken_target;
        else
            ex_actual_npc = ex_pc4;
    end

    // Uniform mispredict check (M5): redirect iff the fetch stage followed a
    // next-PC different from the one this instruction actually produces. With
    // the predictor off, pred_npc is always pc+4 and this reduces exactly to
    // the M3/M4 taken-branch redirect. Suppressed while an M instruction is
    // iterating in EX: the redirect would otherwise re-fire every stall cycle,
    // and ID/EX's bubble-on-redirect would destroy the in-flight M
    // instruction. (With the full-tag BTB an M instruction can never
    // mispredict; the guard enforces the invariant regardless.)
    assign redirect    = idex_valid && !mdu_stall &&
                         (ex_actual_npc != idex_pred_npc);
    assign redirect_pc = ex_actual_npc;

    // BPU training from resolved control instructions.
    logic ex_is_ctrl;
    assign ex_is_ctrl = idex_is_branch || idex_is_jal || idex_is_jalr;
    bpu u_bpu (
        .clk, .rst_n, .mode(cfg_bp_mode),
        .pc_if(pc_if),
        .pred_taken(bp_pred_taken), .pred_target(bp_pred_target),
        .pred_pidx(bp_pred_pidx),
        .up_valid(idex_valid && ex_is_ctrl && !mdu_stall),
        .up_is_cond(idex_is_branch),
        .up_pc(idex_pc),
        .up_taken(idex_is_branch ? ex_branch_taken : 1'b1),
        .up_target(ex_taken_target),
        .up_pidx(idex_bp_pidx)
    );

    // EX/MEM
    logic [XLEN-1:0] exmem_alu_y, exmem_rs2d, exmem_pc4, exmem_pc;
    logic            exmem_valid;
    logic [4:0]      exmem_rd;
    logic [2:0]      exmem_funct3;
    logic [31:0]     exmem_instr;
    logic            exmem_reg_write, exmem_mem_write;
    wb_sel_e         exmem_wb_sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || mdu_stall) begin
            exmem_reg_write <= 1'b0; exmem_mem_write <= 1'b0; exmem_wb_sel <= WB_ALU;
            exmem_alu_y <= '0; exmem_rs2d <= '0; exmem_pc4 <= '0; exmem_pc <= RESET_PC;
            exmem_rd <= 5'd0; exmem_funct3 <= 3'd0; exmem_instr <= 32'h0000_0013;
            exmem_valid <= 1'b0;
        end else begin
            exmem_reg_write <= idex_reg_write; exmem_mem_write <= idex_mem_write;
            exmem_wb_sel <= idex_wb_sel;
            exmem_alu_y <= ex_result; exmem_rs2d <= ex_rs2_fwd; exmem_pc4 <= ex_pc4;
            exmem_pc <= idex_pc; exmem_rd <= idex_rd; exmem_funct3 <= idex_funct3;
            exmem_instr <= idex_instr;
            exmem_valid <= idex_valid;
        end
    end

    // EX/MEM forward source: valid when the instruction writes a register and
    // its value is already known in MEM (ALU result or pc+4) -- i.e. not a load.
    assign exmem_fwd_ok  = exmem_reg_write && (exmem_rd != 5'd0) && (exmem_wb_sel != WB_MEM);
    assign exmem_fwd_val = (exmem_wb_sel == WB_PC4) ? exmem_pc4 : exmem_alu_y;

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
    logic            memwb_reg_write, memwb_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memwb_reg_write <= 1'b0; memwb_data <= '0; memwb_rd <= 5'd0;
            memwb_pc <= RESET_PC; memwb_instr <= 32'h0000_0013;
            memwb_valid <= 1'b0;
        end else begin
            memwb_reg_write <= exmem_reg_write; memwb_data <= mem_wb_data;
            memwb_rd <= exmem_rd; memwb_pc <= exmem_pc; memwb_instr <= exmem_instr;
            memwb_valid <= exmem_valid;
        end
    end

    // ============================================ hazard detection (M3/M4)
    // Load-use: a load in EX whose destination is a source of the instruction
    // in ID. Stall IF/PC one cycle and inject a bubble into EX; the consumer
    // then picks the loaded value up via the MEM/WB forwarding path.
    logic idex_is_load, load_use_stall;
    assign idex_is_load = (idex_wb_sel == WB_MEM) && idex_reg_write;
    assign load_use_stall = idex_is_load && (idex_rd != 5'd0) &&
                            ((idex_rd == id_rs1) || (idex_rd == id_rs2));
    // M4: a multi-cycle M op also stalls the front end while it iterates.
    assign stall = load_use_stall || mdu_stall;

    // ================================================= perf counters (M5)
    // Event definitions:
    //   loaduse / mdu : cycles lost to each stall kind
    //   redirect      : control redirects (every flush; = mispredicted fetch)
    //   br / br_tk    : conditional branches resolved / taken (counted once,
    //                   on the cycle the instruction leaves EX)
    //   br_mp         : conditional branches whose resolution redirected
    logic [31:0] ctr_loaduse, ctr_mdu, ctr_redirect, ctr_br, ctr_br_tk, ctr_br_mp;
    logic ex_adv;                       // EX instruction advances this cycle
    assign ex_adv = idex_valid && !mdu_stall;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctr_loaduse <= '0; ctr_mdu <= '0; ctr_redirect <= '0;
            ctr_br <= '0; ctr_br_tk <= '0; ctr_br_mp <= '0;
        end else begin
            if (load_use_stall) ctr_loaduse <= ctr_loaduse + 1;
            if (mdu_stall)      ctr_mdu     <= ctr_mdu + 1;
            if (redirect)       ctr_redirect<= ctr_redirect + 1;
            if (ex_adv && idex_is_branch) begin
                ctr_br <= ctr_br + 1;
                if (ex_branch_taken) ctr_br_tk <= ctr_br_tk + 1;
                if (redirect)        ctr_br_mp <= ctr_br_mp + 1;
            end
        end
    end
    assign dbg_n_loaduse  = ctr_loaduse;
    assign dbg_n_mdu      = ctr_mdu;
    assign dbg_n_redirect = ctr_redirect;
    assign dbg_n_br       = ctr_br;
    assign dbg_n_br_tk    = ctr_br_tk;
    assign dbg_n_br_mp    = ctr_br_mp;

    // ==================================================== counter CSRs (M4)
    // cycle: every clock. instret: one per *valid* instruction reaching WB
    // (bubbles from flushes/stalls do not count). A CSR read in EX observes
    // the counters as of that cycle; reads are not serialized against
    // still-in-flight older instructions (documented scope limit).
    logic [63:0] csr_cycle, csr_instret;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_cycle   <= 64'd0;
            csr_instret <= 64'd0;
        end else begin
            csr_cycle   <= csr_cycle + 64'd1;
            if (memwb_valid) csr_instret <= csr_instret + 64'd1;
        end
    end
    always_comb begin
        unique case (idex_csr_addr)
            CSR_CYCLE:    csr_rdata = csr_cycle[31:0];
            CSR_CYCLEH:   csr_rdata = csr_cycle[63:32];
            CSR_INSTRET:  csr_rdata = csr_instret[31:0];
            CSR_INSTRETH: csr_rdata = csr_instret[63:32];
            // Non-standard perf counters (custom read-only CSR space).
            CSR_PERF_LOADUSE:  csr_rdata = ctr_loaduse;
            CSR_PERF_MDU:      csr_rdata = ctr_mdu;
            CSR_PERF_REDIRECT: csr_rdata = ctr_redirect;
            CSR_PERF_BR:       csr_rdata = ctr_br;
            CSR_PERF_BR_TK:    csr_rdata = ctr_br_tk;
            CSR_PERF_BR_MP:    csr_rdata = ctr_br_mp;
            default:      csr_rdata = 32'd0;
        endcase
    end

    // ========================================================= WB
    assign wb_reg_write = memwb_reg_write;
    assign wb_rd        = memwb_rd;
    assign wb_data      = memwb_data;

    // ========================================================= debug/trace
    assign dbg_retire     = memwb_valid;
    assign dbg_pc         = memwb_pc;
    assign dbg_instr      = memwb_instr;
    assign dbg_reg_we     = memwb_reg_write && (memwb_rd != 5'd0);
    assign dbg_rd         = memwb_rd;
    assign dbg_wb_data    = memwb_data;
    assign dbg_dmem_we    = exmem_mem_write;
    assign dbg_dmem_addr  = exmem_alu_y;
    assign dbg_dmem_wdata = exmem_rs2d;
endmodule
