// -----------------------------------------------------------------------------
// imem.sv  --  instruction memory (Harvard, read-only, combinational fetch)
// Initialised from a Verilog hex image via +hex=<file> (one 32-bit word/line,
// word 0 == RESET_PC). Word-addressed; byte address is translated internally.
// -----------------------------------------------------------------------------
module imem import riscv_pkg::*; #(
    parameter int unsigned WORDS = 16384          // 64 KiB
) (
    input  logic [XLEN-1:0] addr,                 // byte address (PC)
    output logic [31:0]     rdata
);
    logic [31:0] mem [WORDS];
    string       hexfile;

    initial begin
        for (int i = 0; i < WORDS; i++) mem[i] = 32'h0000_0013;  // NOP (addi x0,x0,0)
        if ($value$plusargs("hex=%s", hexfile))
            $readmemh(hexfile, mem);
    end

    /* verilator lint_off UNUSED */
    logic [XLEN-1:0]          byte_off;   // only [15:2] index a 64 KiB memory
    /* verilator lint_on UNUSED */
    logic [$clog2(WORDS)-1:0] widx;
    assign byte_off = addr - RESET_PC;
    assign widx     = byte_off[$clog2(WORDS)+1 : 2];
    assign rdata    = mem[widx];
endmodule
