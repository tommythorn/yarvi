// -----------------------------------------------------------------------
//
//   Copyright 2016,2018,2019 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a simple RISC-V implementation.

*************************************************************************/

`include "yarvi.h"

module yarvi_fe( input  wire             clock
               , input  wire             reset
               , input  wire             restart
               , input  wire [`VMSB:0]   restart_pc

               , input  wire [`VMSB:0]   address
               , input  wire [   31:0]   writedata
               , input  wire [    3:0]   writemask

               , output reg              fe_valid = 0
               , output reg  [`VMSB:0]   fe_pc
               , output wire [   31:0]   fe_insn);

   reg [31:0] code[(1<<(`PMSB - 1))-1:0];

   wire       we = !reset && address[`VMSB:`PMSB+1] == ('h80000000 >> (`PMSB+1));
   wire [`PMSB-2:0] wi = address[`PMSB:2];
   // This probably cannot be synthesized
   always @(posedge clock) if (we & writemask[0]) code[wi][ 7: 0] <= writedata[ 7: 0];
   always @(posedge clock) if (we & writemask[1]) code[wi][15: 8] <= writedata[15: 8];
   always @(posedge clock) if (we & writemask[2]) code[wi][23:16] <= writedata[23:16];
   always @(posedge clock) if (we & writemask[3]) code[wi][31:24] <= writedata[31:24];

   always @(posedge clock)
     if (reset) begin
        fe_valid <= 0;
        fe_pc    <= `INIT_PC;
     end else if (restart) begin
        fe_valid <= 1;
        fe_pc    <= restart_pc;
     end else begin
        fe_valid <= 1;
        if (fe_valid)
          fe_pc    <= fe_pc + 4;
     end

   assign fe_insn   = code[fe_pc[`PMSB:2]];

   initial $readmemh(`INIT_MEM, code);
endmodule
