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
               , input  wire             restart
               , input  wire [`VMSB:0]   restart_pc

               , input  wire [`VMSB:0]   address
               , input  wire [   31:0]   writedata
               , input  wire [    3:0]   writemask

               , output reg  [`VMSB:0]   fe_pc
               , output wire [   31:0]   fe_insn);

   reg [31:0] code[(1<<(`PMSB - 1))-1:0];
   assign fe_insn = code[fe_pc[`PMSB:2]];

   wire [`PMSB-2:0] wi = address[`PMSB:2];
   // This probably cannot be synthesized
   always @(posedge clock) if (writemask[0]) code[wi][ 7: 0] <= writedata[ 7: 0];
   always @(posedge clock) if (writemask[1]) code[wi][15: 8] <= writedata[15: 8];
   always @(posedge clock) if (writemask[2]) code[wi][23:16] <= writedata[23:16];
   always @(posedge clock) if (writemask[3]) code[wi][31:24] <= writedata[31:24];

   always @(posedge clock) fe_pc <= restart ? restart_pc : fe_pc + 4;
   initial $readmemh(`INIT_MEM, code);
endmodule
