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

               , output reg  [`VMSB:0]   fe_pc = `INIT_PC
               , output wire [31:0]      fe_insn);

   reg  [31:0]             code[1023:0];

   always @(posedge clock) fe_pc   <= restart ? restart_pc : fe_pc + 4;
   assign                  fe_insn  = code[fe_pc[11:2]];

   initial $readmemh("rv64ui-p-simple.hex", code);
endmodule
