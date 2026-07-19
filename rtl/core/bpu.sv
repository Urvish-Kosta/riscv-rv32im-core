// -----------------------------------------------------------------------------
// bpu.sv  --  branch prediction unit (milestone M5)
//
// Predicts at IF: a direct-mapped BTB (64 entries) supplies the target and the
// instruction kind; a 256-entry table of 2-bit saturating counters (PHT)
// supplies the direction for conditional branches. Unconditional entries
// (JAL/JALR) predict taken on a BTB hit.
//
//   mode 0 (off)     : always predict not-taken / fall-through
//   mode 1 (bimodal) : PHT indexed by pc[9:2]
//   mode 2 (gshare)  : PHT indexed by pc[9:2] XOR GHR (8-bit global history)
//
// Design notes:
//   * The BTB tag is the *full* remaining PC (pc[31:8] for a 64-entry table of
//     word-aligned PCs): false hits are impossible, so a non-control
//     instruction can never be predicted taken. This keeps the pipeline's
//     mispredict handling a pure performance path, never a correctness one.
//   * The GHR is updated non-speculatively at EX (resolved direction of
//     conditional branches, oldest-first since EX is in order). Speculative
//     history with checkpoint/repair would predict slightly better on tight
//     dependent branch pairs; the simpler scheme is chosen and documented
//     (decision #018).
//   * Update port is driven from EX for every resolved control instruction:
//     allocate/refresh the BTB, train the PHT (conditional only), shift GHR.
// -----------------------------------------------------------------------------
module bpu import riscv_pkg::*; (
    input  logic            clk,
    input  logic            rst_n,
    input  logic [1:0]      mode,        // 0 off, 1 bimodal, 2 gshare

    // predict (IF)
    /* verilator lint_off UNUSED */
    input  logic [XLEN-1:0] pc_if,     // [1:0] unused: PCs are word-aligned
    /* verilator lint_on UNUSED */
    output logic            pred_taken,
    output logic [XLEN-1:0] pred_target,
    output logic [7:0]      pred_pidx,   // PHT index used for this prediction
                                         // (carried down the pipe; the update
                                         // must train the same counter)

    // update (EX, resolved)
    input  logic            up_valid,    // control instruction resolved in EX
    input  logic            up_is_cond,  // conditional branch (vs JAL/JALR)
    /* verilator lint_off UNUSED */
    input  logic [XLEN-1:0] up_pc,     // [1:0] unused: PCs are word-aligned
    /* verilator lint_on UNUSED */
    input  logic            up_taken,    // actual direction (1 for jumps)
    input  logic [XLEN-1:0] up_target,   // actual taken-target
    input  logic [7:0]      up_pidx      // predict-time PHT index of this instr
);
    localparam int unsigned BTB_ENTRIES = 64;
    localparam int unsigned PHT_ENTRIES = 256;
    localparam int unsigned BTB_IDX_W   = $clog2(BTB_ENTRIES);   // 6
    localparam int unsigned PHT_IDX_W   = $clog2(PHT_ENTRIES);   // 8
    localparam int unsigned TAG_W       = XLEN - 2 - BTB_IDX_W;  // full tag: 24

    typedef struct packed {
        logic             valid;
        logic             is_cond;
        logic [TAG_W-1:0] tag;
        logic [XLEN-1:0]  target;
    } btb_entry_t;

    btb_entry_t             btb [BTB_ENTRIES];
    logic [1:0]             pht [PHT_ENTRIES];
    logic [PHT_IDX_W-1:0]   ghr;

    // ---- predict ----
    logic [BTB_IDX_W-1:0] p_bidx;
    logic [TAG_W-1:0]     p_tag;
    logic [PHT_IDX_W-1:0] p_pidx;
    btb_entry_t           p_ent;
    logic                 p_hit, p_dir;

    assign p_bidx = pc_if[2 +: BTB_IDX_W];
    assign p_tag  = pc_if[XLEN-1 : 2+BTB_IDX_W];
    assign p_ent  = btb[p_bidx];
    assign p_hit  = p_ent.valid && (p_ent.tag == p_tag);
    assign p_pidx = (mode == 2'd2) ? (pc_if[2 +: PHT_IDX_W] ^ ghr)
                                   :  pc_if[2 +: PHT_IDX_W];
    assign p_dir  = p_ent.is_cond ? pht[p_pidx][1] : 1'b1;   // uncond: taken

    assign pred_taken  = (mode != 2'd0) && p_hit && p_dir;
    assign pred_target = p_ent.target;
    assign pred_pidx   = p_pidx;

    // ---- update ----
    logic [BTB_IDX_W-1:0] u_bidx;
    logic [TAG_W-1:0]     u_tag;
    logic [PHT_IDX_W-1:0] u_pidx;

    assign u_bidx = up_pc[2 +: BTB_IDX_W];
    assign u_tag  = up_pc[XLEN-1 : 2+BTB_IDX_W];
    // Train exactly the counter that made the prediction. Recomputing the
    // index here from the *current* GHR would train a different entry
    // whenever other branches resolved between predict and update -- a real
    // bug this design had first; fixed by carrying the index (see
    // docs/design-decisions.md #018).
    assign u_pidx = up_pidx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            /* verilator lint_off BLKSEQ */
            for (int i = 0; i < BTB_ENTRIES; i++) btb[i] = '0;
            for (int i = 0; i < PHT_ENTRIES; i++) pht[i] = 2'b01; // weak NT
            /* verilator lint_on BLKSEQ */
            ghr <= '0;
        end else if (up_valid) begin
            // BTB: allocate/refresh (taken-target cached; harmless if the
            // entry later predicts not-taken)
            btb[u_bidx] <= '{valid: 1'b1, is_cond: up_is_cond,
                             tag: u_tag, target: up_target};
            if (up_is_cond) begin
                // 2-bit saturating counter
                if (up_taken  && pht[u_pidx] != 2'b11) pht[u_pidx] <= pht[u_pidx] + 2'b01;
                if (!up_taken && pht[u_pidx] != 2'b00) pht[u_pidx] <= pht[u_pidx] - 2'b01;
                ghr <= {ghr[PHT_IDX_W-2:0], up_taken};
            end
        end
    end
endmodule
