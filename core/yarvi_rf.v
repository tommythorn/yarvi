// -----------------------------------------------------------------------
//
//   Copyright 2016,2018 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a simple RISC-V RV64I implementation.

*************************************************************************/

`include "yarvi.h"

module yarvi_rf( input  wire             clock

               , input  wire [`VMSB:0]   pc
               , input  wire [31:0]      insn
               , input  wire             we
               , input  wire [ 4:0]      addr
               , input  wire [`XMSB:0]   d

               , output reg  [`VMSB:0]   rf_pc
               , output reg  [31:0]      rf_insn
               , output wire [`VMSB:0]   rf_rs1_val
               , output wire [`VMSB:0]   rf_rs2_val);

   reg [`VMSB:0] regs[0:31];
   reg [ 4:0] rp1 = 0, rp2 = 0;

   always @(posedge clock) rf_pc      <= pc;
   always @(posedge clock) rf_insn    <= insn;

   always @(posedge clock) if (we) regs[addr] <= d;

//   always @(posedge clock) rp1 <= we & insn`rs1 == addr ? 'hx : insn`rs1;
   always @(posedge clock) rp1 <= insn`rs1;
//   always @(posedge clock) rp2 <= we & insn`rs2 == addr ? 'hx : insn`rs2;
   always @(posedge clock) rp2 <= insn`rs2;

   // Bypass writes.  Bypassing will be unified in future
   assign rf_rs1_val = we & rp1 == addr ? d : regs[rp1];
   assign rf_rs2_val = we & rp2 == addr ? d : regs[rp2];

   reg [5:0] i;
   initial
      for (i = 0; i < 32; i = i + 1) regs[i] = i;
endmodule
