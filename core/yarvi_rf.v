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
               , input  wire [ 4:0]      wb_rd
               , input  wire [`XMSB:0]   wb_val

               , output wire             rf_valid
               , output reg  [`VMSB:0]   rf_pc
               , output reg  [31:0]      rf_insn
               , output wire [`VMSB:0]   rf_rs1_val
               , output wire [`VMSB:0]   rf_rs2_val);

   reg [`VMSB:0] regs[0:31];
   reg [ 4:0] rp1, rp2;

   assign rf_valid = 1'd 1;

   always @(posedge clock) begin
      rf_pc         <= pc;
      rf_insn       <= insn;
      rp1           <= insn`rs1;
      rp2           <= insn`rs2;
      if (|wb_rd)
         regs[wb_rd] <= wb_val;
   end

   assign rf_rs1_val = regs[rp1];
   assign rf_rs2_val = regs[rp2];

   reg [31:0] i;
   initial for (i = 0; i < 32; i = i + 1) regs[i[4:0]] = {26'd0,i[5:0]};
endmodule
