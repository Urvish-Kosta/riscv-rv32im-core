// -----------------------------------------------------------------------------
// mdu.sv  --  iterative RV32M multiply/divide unit (milestone M4)
//
// 32-iteration shift-add multiplier and restoring divider on magnitudes, with
// sign fix-up at the end. Division special cases (divide-by-zero, and the
// signed-overflow case MIN_INT / -1) resolve in a single cycle with the
// results the RISC-V M spec defines.
//
// Handshake: `start` is asserted while an M instruction sits in EX and the
// unit is idle; `busy` while iterating; `done` pulses for one cycle with
// `result` valid, letting the instruction advance.
//
// Implementation notes (each fixes a classic trap):
//   * the multiplier's high-word add keeps its carry: 33-bit sum shifted back
//     in ({sum[32:0], lo[31:1]}), otherwise large operands lose a bit;
//   * the divider's partial remainder is 33 bits: after a restoring step the
//     remainder can reach divisor-1 (bit 31 set), so shifting a 32-bit
//     remainder would drop its MSB;
//   * MUL needs no sign handling at all -- the low 32 product bits are
//     identical regardless of operand signedness, so it multiplies raw values.
//
// Semantics reference: riscv_pkg::mdu_func. This RTL must agree with it; the
// differential tests exist to prove that agreement.
// -----------------------------------------------------------------------------
module mdu import riscv_pkg::*; (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  mdu_op_e     op,
    input  logic [31:0] a,          // rs1 (multiplicand / dividend)
    input  logic [31:0] b,          // rs2 (multiplier / divisor)
    output logic        busy,
    output logic        done,
    output logic [31:0] result
);
    typedef enum logic [1:0] { S_IDLE, S_RUN, S_DONE } state_e;
    state_e state;

    logic        neg_res, neg_rem;
    logic [4:0]  cnt;
    mdu_op_e     op_q;

    logic [63:0] prod;              // multiplier accumulator {hi, lo}
    /* verilator lint_off UNUSED */
    logic [32:0] rem;   // 33-bit partial remainder; bit 32 is compare headroom
    /* verilator lint_on UNUSED */
    logic [31:0] quo, div_b, b_q;

    // Magnitudes for the signed variants. MUL uses raw operands (low 32 bits
    // of the product are signedness-independent); MULHU uses raw; MULHSU
    // takes |a| only (b is unsigned).
    logic [31:0] abs_a, abs_b;
    assign abs_a = (a[31] && (op == MDU_MULH || op == MDU_MULHSU ||
                              op == MDU_DIV  || op == MDU_REM)) ? (~a + 32'd1) : a;
    assign abs_b = (b[31] && (op == MDU_MULH ||
                              op == MDU_DIV  || op == MDU_REM)) ? (~b + 32'd1) : b;

    // Divide special cases: defined results, no iteration needed.
    logic        div_special;
    logic [31:0] div_special_res;
    always_comb begin
        div_special     = 1'b0;
        div_special_res = 32'd0;
        if (op == MDU_DIV || op == MDU_DIVU || op == MDU_REM || op == MDU_REMU) begin
            if (b == 32'd0) begin
                div_special = 1'b1;
                unique case (op)
                    MDU_DIV, MDU_DIVU: div_special_res = 32'hFFFF_FFFF;
                    default:           div_special_res = a;        // REM/REMU
                endcase
            end else if ((op == MDU_DIV || op == MDU_REM) &&
                         a == 32'h8000_0000 && b == 32'hFFFF_FFFF) begin
                div_special = 1'b1;
                div_special_res = (op == MDU_DIV) ? 32'h8000_0000 : 32'd0;
            end
        end
    end

    // One multiplier step: add-with-carry into the high word, shift right.
    logic [32:0] mul_sum;
    assign mul_sum = {1'b0, prod[63:32]} + {1'b0, b_q};

    // One restoring-divider step: shift the next dividend bit into a 33-bit
    // remainder, compare, conditionally subtract.
    logic [32:0] rem_sh;
    assign rem_sh = {rem[31:0], quo[31]};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; busy <= 1'b0; done <= 1'b0; result <= '0;
            prod <= '0; rem <= '0; quo <= '0; div_b <= '0; b_q <= '0;
            cnt <= '0; op_q <= MDU_MUL; neg_res <= 1'b0; neg_rem <= 1'b0;
        end else begin
            done <= 1'b0;
            unique case (state)
                S_IDLE: if (start) begin
                    op_q    <= op;
                    neg_res <= ((op == MDU_MULH  ) && (a[31] ^ b[31])) ||
                               ((op == MDU_MULHSU) &&  a[31]         ) ||
                               ((op == MDU_DIV   ) && (a[31] ^ b[31]));
                    neg_rem <= (op == MDU_REM) && a[31];
                    if (div_special) begin
                        result <= div_special_res;
                        done   <= 1'b1;
                    end else begin
                        prod  <= {32'd0, (op == MDU_MUL || op == MDU_MULHU) ? a : abs_a};
                        b_q   <= (op == MDU_MUL || op == MDU_MULHU) ? b : abs_b;
                        rem   <= 33'd0;
                        quo   <= abs_a;
                        div_b <= abs_b;
                        cnt   <= 5'd31;
                        busy  <= 1'b1;
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    // multiply step (harmless during divides and vice versa)
                    if (prod[0]) prod <= {mul_sum, prod[31:1]};
                    else         prod <= {1'b0, prod[63:1]};
                    // divide step
                    if (rem_sh >= {1'b0, div_b}) begin
                        rem <= rem_sh - {1'b0, div_b};
                        quo <= {quo[30:0], 1'b1};
                    end else begin
                        rem <= rem_sh;
                        quo <= {quo[30:0], 1'b0};
                    end
                    if (cnt == 5'd0) state <= S_DONE;
                    else             cnt   <= cnt - 5'd1;
                end
                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    unique case (op_q)
                        MDU_MUL:    result <= prod[31:0];
                        MDU_MULH, MDU_MULHSU, MDU_MULHU: begin
                            if (neg_res) begin
                                /* verilator lint_off UNUSED */
                                automatic logic [63:0] negp = (~prod) + 64'd1;  // low word unused: MULH* returns the high word
                                /* verilator lint_on UNUSED */
                                result <= negp[63:32];
                            end else
                                result <= prod[63:32];
                        end
                        MDU_DIV, MDU_DIVU:
                            result <= neg_res ? (~quo + 32'd1) : quo;
                        default:                                  // REM/REMU
                            result <= neg_rem ? (~rem[31:0] + 32'd1) : rem[31:0];
                    endcase
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
