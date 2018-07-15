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

               , input  wire             valid
               , input  wire [`VMSB:0]   pc
               , input  wire [31:0]      insn
               // Write back port
               , input  wire             we
               , input  wire [ 4:0]      addr
               , input  wire [63:0]      d

               , output reg              rf_valid = 0
               , output reg  [`VMSB:0]   rf_pc
               , output reg  [31:0]      rf_insn
               , output reg  [63:0]      rf_rs1_val
               , output reg  [63:0]      rf_rs2_val);

   reg [63:0] regs[0:31];
   always @(posedge clock) if (we) regs[addr] <= d;
   always @(posedge clock) rf_valid   <= valid;
   always @(posedge clock) rf_insn    <= insn;
   always @(posedge clock) rf_pc      <= pc;
   always @(posedge clock) rf_rs1_val <= regs[insn`rs1];
   always @(posedge clock) rf_rs2_val <= regs[insn`rs2];

   always @(posedge clock)
     if (we)
       $display("%05d                                            x%1d <- 0x%x", $time, addr, d);

   initial regs[0] = 0;
endmodule
