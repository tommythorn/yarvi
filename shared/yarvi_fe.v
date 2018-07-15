// -----------------------------------------------------------------------
//
//   Copyright 2016,2018 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a simple RISC-V RV64I implementation.

*************************************************************************/

`include "yarvi.h"

module yarvi_fe( input  wire             clock
               , input                   restart
               , input       [`VMSB:0]   restart_pc

               , output reg              fe_valid = 0
               , output reg  [`VMSB:0]   fe_pc
               , output reg  [31:0]      fe_insn);

   reg  [31:0]             code[1023:0];
   reg  [`VMSB:0]          internal_pc  = `INIT_PC;
   wire [`VMSB:0]          pc           = restart ? restart_pc : internal_pc;
   always @(posedge clock) internal_pc <= pc + (`VMSB 'd 4);
   always @(posedge clock) fe_valid    <= 1;
   always @(posedge clock) fe_pc       <= pc;
   always @(posedge clock) fe_insn     <= code[pc[11:2]];
   initial $readmemh("rv64ui-p-simple.hex", code);
endmodule
