// -----------------------------------------------------------------------------
// main.cpp  --  Verilator test harness (shared by both cores)
//
// Selects the DUT at compile time:
//   -DDUT_PIPE  -> core_pipe  (5-stage pipeline, M2)
//   (default)   -> core_top   (single-cycle reference, M1)
//
// Loads a program via +hex=<file> (consumed by the RTL memories), runs the core,
// and implements the HTIF `tohost` exit protocol: a store to TOHOST ends the
// simulation. tohost value 1 => PASS (exit 0); value (N<<1)|1 => FAIL code N.
// On halt the raw 32-bit tohost value is printed, so a driver can compare the
// pipeline against the single-cycle reference bit-for-bit.
//
//   ./Vcore_top  +hex=prog.hex [+max_cycles=N] [+trace]
//   ./Vcore_pipe +hex=prog.hex [+max_cycles=N] [+trace]
// -----------------------------------------------------------------------------
#include <verilated.h>

#if defined(DUT_PIPE)
  #include "Vcore_pipe.h"
  using Dut = Vcore_pipe;
#else
  #include "Vcore_top.h"
  using Dut = Vcore_top;
#endif

#if VM_TRACE
#include <verilated_vcd_c.h>
#endif

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>

static const uint32_t TOHOST = 0x80001000u;

static uint64_t plusarg_u(VerilatedContext* ctx, const char* key, uint64_t dflt) {
    const char* m  = ctx->commandArgsPlusMatch(key);   // "+key=value" or ""
    const char* eq = std::strchr(m, '=');
    return eq ? std::strtoull(eq + 1, nullptr, 0) : dflt;
}
static bool plusarg_set(VerilatedContext* ctx, const char* key) {
    return ctx->commandArgsPlusMatch(key)[0] != '\0';
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> ctx{new VerilatedContext};
    ctx->commandArgs(argc, argv);

    const uint64_t max_cycles = plusarg_u(ctx.get(), "max_cycles", 100000);
    const bool     trace_on   = plusarg_set(ctx.get(), "trace");

    const std::unique_ptr<Dut> dut{new Dut{ctx.get()}};

#if VM_TRACE
    std::unique_ptr<VerilatedVcdC> tfp;
    if (trace_on) {
        ctx->traceEverOn(true);
        tfp.reset(new VerilatedVcdC);
        dut->trace(tfp.get(), 99);
        tfp->open("wave.vcd");
    }
#endif

    uint64_t tt = 0;
    auto half = [&](int level) {
        dut->clk = level;
        dut->eval();
#if VM_TRACE
        if (tfp) tfp->dump(tt);
#endif
        ++tt;
    };

    // Reset (active-low) for 2 clocks.
    dut->rst_n = 0; dut->clk = 0; dut->eval();
    half(0); half(1); half(0); half(1);
    dut->rst_n = 1;

    int      exit_code = -1;
    uint32_t tohost_val = 0;
    uint64_t cyc = 0;
    for (; cyc < max_cycles; ++cyc) {
        half(0);   // low phase: combinational settled

        if (trace_on) {
            std::printf("[%6llu] pc=%08x instr=%08x",
                        (unsigned long long)cyc,
                        (unsigned)dut->dbg_pc, (unsigned)dut->dbg_instr);
            if (dut->dbg_reg_we)
                std::printf(" x%-2u<=%08x", (unsigned)dut->dbg_rd, (unsigned)dut->dbg_wb_data);
            if (dut->dbg_dmem_we)
                std::printf(" MEM[%08x]<=%08x",
                            (unsigned)dut->dbg_dmem_addr, (unsigned)dut->dbg_dmem_wdata);
            std::printf("\n");
        }

        if (dut->dbg_dmem_we && dut->dbg_dmem_addr == TOHOST) {
            tohost_val = dut->dbg_dmem_wdata;
            exit_code  = (tohost_val == 1u) ? 0 : (int)(tohost_val >> 1);
            half(1);
            break;
        }
        half(1);   // high phase: posedge commits state
    }

#if VM_TRACE
    if (tfp) tfp->close();
#endif

    if (exit_code < 0) {
        std::printf("[core] TIMEOUT after %llu cycles (no tohost write)\n",
                    (unsigned long long)cyc);
        return 124;
    }
    std::printf("[core] halted @cycle %llu  tohost=0x%08x  ->  %s (exit=%d)\n",
                (unsigned long long)cyc, tohost_val,
                exit_code == 0 ? "PASS" : "FAIL", exit_code);
    return exit_code;
}
