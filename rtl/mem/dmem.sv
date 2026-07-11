// -----------------------------------------------------------------------------
// dmem.sv  --  data memory (Harvard, R/W, single-cycle)
//   * combinational full-word read (core extracts byte/half + extends)
//   * synchronous write with byte/half/word masking (posedge)
// Initialised from the same +hex image as imem so a program's static data
// (e.g. the HTIF tohost word) is present. Word-addressed.
// -----------------------------------------------------------------------------
module dmem import riscv_pkg::*; #(
    parameter int unsigned WORDS = 16384          // 64 KiB
) (
    input  logic            clk,
    input  logic [XLEN-1:0] addr,                 // byte address
    input  logic            we,
    input  logic [1:0]      size,                 // 00=byte 01=half 10=word
    input  logic [XLEN-1:0] wdata,
    output logic [XLEN-1:0] rword                 // raw aligned word
);
    logic [31:0] mem [WORDS];
    string       hexfile;

    initial begin
        for (int i = 0; i < WORDS; i++) mem[i] = 32'h0;
        if ($value$plusargs("hex=%s", hexfile))
            $readmemh(hexfile, mem);
    end

    /* verilator lint_off UNUSED */
    logic [XLEN-1:0]          byte_off;   // only [15:2] index a 64 KiB memory
    /* verilator lint_on UNUSED */
    logic [$clog2(WORDS)-1:0] widx;
    logic [1:0]               boff;
    assign byte_off = addr - RESET_PC;
    assign widx     = byte_off[$clog2(WORDS)+1 : 2];
    assign boff     = addr[1:0];

    assign rword = mem[widx];

    always_ff @(posedge clk) begin
        if (we) begin
            unique case (size)
                2'b00: mem[widx][{boff, 3'b000} +: 8]      <= wdata[7:0];   // SB
                2'b01: mem[widx][{addr[1], 4'b0000} +: 16] <= wdata[15:0];  // SH (halfword aligned)
                default: mem[widx]                         <= wdata;        // SW
            endcase
        end
    end
endmodule
