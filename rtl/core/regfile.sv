// -----------------------------------------------------------------------------
// regfile.sv  --  32x32 integer register file
//   * x0 hardwired to 0 (writes discarded, reads return 0)
//   * synchronous write (posedge), combinational read
// Single-cycle core: rd of an instruction is written the same cycle its sources
// are read, but they belong to the *same* instruction, so there is no hazard.
// -----------------------------------------------------------------------------
module regfile import riscv_pkg::*; (
    input  logic            clk,
    input  logic            we,
    input  logic [4:0]      rs1_addr,
    input  logic [4:0]      rs2_addr,
    input  logic [4:0]      rd_addr,
    input  logic [XLEN-1:0] rd_data,
    output logic [XLEN-1:0] rs1_data,
    output logic [XLEN-1:0] rs2_data
);
    logic [XLEN-1:0] regs [32];

    initial begin
        for (int i = 0; i < 32; i++) regs[i] = '0;
    end

    always_ff @(posedge clk) begin
        if (we && rd_addr != 5'd0)
            regs[rd_addr] <= rd_data;
    end

    assign rs1_data = (rs1_addr == 5'd0) ? '0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? '0 : regs[rs2_addr];
endmodule
