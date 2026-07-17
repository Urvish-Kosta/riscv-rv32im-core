// -----------------------------------------------------------------------------
// tb_mdu.sv  --  standalone unit test: iterative mdu vs. behavioural mdu_func
//
// Drives directed edge cases plus seeded random vectors through the iterative
// unit and compares every result with riscv_pkg::mdu_func (the behavioural
// spec encoding). Self-checking; prints a summary and finishes with a
// non-zero exit on mismatch.  Run: make -C sim/verilator mdu_tb
// -----------------------------------------------------------------------------
module tb_mdu import riscv_pkg::*;;

    logic clk, rst_n;
    logic start;
    mdu_op_e op;
    logic [31:0] a, b;
    /* verilator lint_off UNUSED */
    logic busy;   // handshake port; this TB polls `done` only
    /* verilator lint_on UNUSED */
    logic done;
    logic [31:0] result;

    mdu dut (.*);

    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */

    int n_pass = 0, n_fail = 0;

    task automatic run_one(input mdu_op_e t_op, input logic [31:0] t_a, t_b);
        logic [31:0] expect_v;
        expect_v = mdu_func(t_op, t_a, t_b);
        @(negedge clk);
        op = t_op; a = t_a; b = t_b; start = 1;
        @(negedge clk);
        start = 0;
        // wait for done (special cases: 1 cycle; iterative: ~34)
        for (int i = 0; i < 64 && !done; i++) @(negedge clk);
        if (!done) begin
            $display("FAIL op=%0d a=%08x b=%08x : TIMEOUT", t_op, t_a, t_b);
            n_fail++;
        end else if (result !== expect_v) begin
            $display("FAIL op=%0d a=%08x b=%08x : got %08x expect %08x",
                     t_op, t_a, t_b, result, expect_v);
            n_fail++;
        end else n_pass++;
        @(negedge clk);
    endtask

    localparam logic [31:0] EDGE [8] = '{
        32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF, 32'h8000_0000,
        32'h7FFF_FFFF, 32'h0000_0002, 32'hAAAA_5555, 32'h0001_0000
    };

    initial begin
        clk = 0; rst_n = 0;
        start = 0; op = MDU_MUL; a = 0; b = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // all ops x all edge pairs (8 ops * 64 pairs = 512 directed cases)
        for (int o = 0; o < 8; o++)
            for (int i = 0; i < 8; i++)
                for (int j = 0; j < 8; j++)
                    run_one(mdu_op_e'(o), EDGE[i], EDGE[j]);

        // seeded random vectors
        void'($urandom(32'd42));
        for (int k = 0; k < 500; k++)
            run_one(mdu_op_e'($urandom_range(0,7)), $urandom(), $urandom());

        $display("[tb_mdu] pass=%0d fail=%0d", n_pass, n_fail);
        if (n_fail != 0) $fatal(1, "tb_mdu FAILED");
        $finish;
    end
endmodule
