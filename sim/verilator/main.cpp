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
//   ./Vcore_top  +hex=prog.hex [+max_cycles=N] [+vcd] [+trace_file=f]
//   ./Vcore_pipe +hex=prog.hex [+max_cycles=N] [+vcd] [+trace_file=f]
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
#include <string>
#include <cstring>
#include <memory>

static const uint32_t TOHOST = 0x80001000u;

static uint64_t plusarg_u(VerilatedContext* ctx, const char* key, uint64_t dflt) {
    const char* m  = ctx->commandArgsPlusMatch(key);   // "+key=value" or ""
    const char* eq = std::strchr(m, '=');
    return eq ? std::strtoull(eq + 1, nullptr, 0) : dflt;
}
// NOTE: commandArgsPlusMatch() matches by *prefix*, so a query for "trace"
// also matches "+trace_file=...". Require the matched argument to be exactly
// "+<key>" so the flags stay independent. (This bug made every +trace_file
// run also dump a full VCD -- hundreds of MB on a long benchmark.)
static bool plusarg_set(VerilatedContext* ctx, const char* key) {
    const std::string m = ctx->commandArgsPlusMatch(key);
    return m == (std::string("+") + key);
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> ctx{new VerilatedContext};
    ctx->commandArgs(argc, argv);

    const uint64_t max_cycles = plusarg_u(ctx.get(), "max_cycles", 100000);
    const bool     trace_on   = plusarg_set(ctx.get(), "vcd");   // +vcd -> wave.vcd

    // +trace_file=<path>: machine-readable *retire* trace. One record per
    // architecturally committed instruction, identical in format for both
    // cores, so tools/trace_compare.py can diff them instruction-by-
    // instruction (the same shape as a Spike lockstep comparison, using the
    // verified single-cycle core as the golden model).
    std::FILE* tf = nullptr;
    {
        const char* m  = ctx->commandArgsPlusMatch("trace_file");
        const char* eq = std::strchr(m, '=');
        if (eq) {
            tf = std::fopen(eq + 1, "w");
            if (!tf) { std::fprintf(stderr, "cannot open trace file %s\n", eq + 1); return 2; }
            std::fprintf(tf, "# cycle pc instr rd wdata memaddr memdata\n");
        }
    }

    const std::unique_ptr<Dut> dut{new Dut{ctx.get()}};

#if defined(DUT_PIPE)
    // Branch predictor mode: +bp=off|bimodal|gshare (default gshare).
    {
        const char* m  = ctx->commandArgsPlusMatch("bp");
        const char* eq = std::strchr(m, '=');
        const char* v  = eq ? eq + 1 : "gshare";
        if      (!std::strcmp(v, "off"))     dut->cfg_bp_mode = 0;
        else if (!std::strcmp(v, "bimodal")) dut->cfg_bp_mode = 1;
        else                                 dut->cfg_bp_mode = 2;
    }
#endif

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
    uint64_t cyc = 0, retired = 0;
    // Performance is measured at the halt cycle. After the halting store
    // commits (in MEM on the pipeline) the simulator runs a few extra cycles
    // *for the trace only*, so the retiring stream drains and both cores emit
    // identical retire traces. These drain cycles are excluded from the
    // reported cycle/retire counts.
    uint64_t halt_cyc = 0, halt_retired = 0;
    int      drain = -1;
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

#if defined(DUT_PIPE)
        const bool retire_now = dut->dbg_retire;
#else
        const bool retire_now = true;   // single-cycle: one retire per cycle
#endif
        if (retire_now) ++retired;

        // The trace ends exactly when the halting store *retires*, so both
        // cores produce identical retire streams regardless of pipeline depth.
        bool halt_store_retired = false;
        if (tf && retire_now) {
            std::fprintf(tf, "%llu %08x %08x ", (unsigned long long)cyc,
                         (unsigned)dut->dbg_pc, (unsigned)dut->dbg_instr);
            if (dut->dbg_reg_we)
                std::fprintf(tf, "x%u %08x ", (unsigned)dut->dbg_rd,
                             (unsigned)dut->dbg_wb_data);
            else
                std::fprintf(tf, "- - ");
            if (dut->dbg_r_mem_we) {
                std::fprintf(tf, "%08x %08x\n", (unsigned)dut->dbg_r_mem_addr,
                             (unsigned)dut->dbg_r_mem_data);
                if (dut->dbg_r_mem_addr == TOHOST) halt_store_retired = true;
            } else {
                std::fprintf(tf, "- -\n");
            }
        }

        if (drain < 0 && dut->dbg_dmem_we && dut->dbg_dmem_addr == TOHOST) {
            tohost_val   = dut->dbg_dmem_wdata;
            exit_code    = (tohost_val == 1u) ? 0 : (int)(tohost_val >> 1);
            halt_cyc     = cyc;
            halt_retired = retired;
            if (!tf) { half(1); break; }   // no trace: stop immediately
            drain = 4;                     // trace-only drain of the pipe
        } else if (drain >= 0 && --drain < 0) {
            half(1);
            break;
        }
        // Stop as soon as the halting store has retired: both cores then emit
        // exactly the same retire stream, whatever their pipeline depth.
        if (halt_store_retired) { half(1); break; }
        half(1);   // high phase: posedge commits state
    }

#if VM_TRACE
    if (tfp) tfp->close();
#endif
    if (tf) std::fclose(tf);

    if (exit_code < 0) {
        std::printf("[core] TIMEOUT after %llu cycles (no tohost write)\n",
                    (unsigned long long)cyc);
        return 124;
    }
    std::printf("[core] halted @cycle %llu  tohost=0x%08x  ->  %s (exit=%d)\n",
                (unsigned long long)halt_cyc, tohost_val,
                exit_code == 0 ? "PASS" : "FAIL", exit_code);
#if !defined(DUT_PIPE)
    if (halt_retired > 0)
        std::printf("[perf] cycles=%llu retired=%llu cpi=%.3f (single-cycle reference)\n",
                    (unsigned long long)halt_cyc, (unsigned long long)halt_retired,
                    (double)halt_cyc / (double)halt_retired);
#endif
#if defined(DUT_PIPE)
    // Measured performance report (pipeline only). Every number below is
    // observed in this run -- nothing is estimated.
    if (halt_retired > 0)
        std::printf("[perf] cycles=%llu retired=%llu cpi=%.3f "
                    "stall_loaduse=%u stall_mdu=%u redirects=%u "
                    "branches=%u taken=%u br_mispred=%u\n",
                    (unsigned long long)halt_cyc, (unsigned long long)halt_retired,
                    (double)halt_cyc / (double)halt_retired,
                    (unsigned)dut->dbg_n_loaduse, (unsigned)dut->dbg_n_mdu,
                    (unsigned)dut->dbg_n_redirect, (unsigned)dut->dbg_n_br,
                    (unsigned)dut->dbg_n_br_tk, (unsigned)dut->dbg_n_br_mp);
#endif
    return exit_code;
}
