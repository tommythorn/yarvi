#include "Vyarvi.h"
#include "verilated.h"

#if VM_TRACE
# include <verilated_vcd_c.h>
#endif

vluint64_t main_time = 0;
double sc_time_stamp() {return main_time;}

int main(int argc, char** argv, char** env) {
    Verilated::commandArgs(argc, argv);
    Verilated::debug(0);
    Verilated::randReset(2);
    Vyarvi* top = new Vyarvi;

#if VM_TRACE
    VerilatedVcdC* tfp = NULL;
    const char* flag = Verilated::commandArgsPlusMatch("trace");
    if (flag && strcmp(flag, "+trace") == 0) {
        Verilated::traceEverOn(true);
        VL_PRINTF("Enabling waves into logs/vlt_dump.vcd...\n");
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);  // Trace 99 levels of hierarchy
        Verilated::mkdir("logs");
        tfp->open("logs/vlt_dump.vcd");
    }
#endif

    top->clock = 0;
    top->reset = 1;

    while (!Verilated::gotFinish()) {
      main_time++;
      top->clock ^= 1;

      if (main_time > 10)
        top->reset = 0;

      // Fast output
      if (0 && top->clock == 0)
        if (top->me_wb_rd)
          VL_PRINTF("%5" VL_PRI64 "d %d %08x %08x r%2d %08x\n", main_time, top->me_priv, top->me_pc, top->me_insn, top->me_wb_rd, top->me_wb_val);
        else
          VL_PRINTF("%5" VL_PRI64 "d %d %08x %08x\n", main_time, top->me_priv, top->me_pc, top->me_insn);

      // Very fast output
      //      if (((main_time >> 4) & 31) == 0)
      //  VL_PRINTF("%04x\n", 0xFFFF & top->me_pc);

      top->eval();

#if VM_TRACE
        // Dump trace data for this cycle
        if (tfp) tfp->dump(main_time);
#endif
    }

    top->final();

#if VM_TRACE
    if (tfp) { tfp->close(); tfp = NULL; }
#endif

#if VM_COVERAGE
    Verilated::mkdir("logs");
    VerilatedCov::write("logs/coverage.dat");
#endif

    delete top; top = NULL;
    exit(0);}
