// -----------------------------------------------------------------------
//
//   Copyright 2016,2018,2020 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

Store alignment

*************************************************************************/

/* The width comparisons in Verilator are completely broken. */
/* verilator lint_off WIDTH */

`include "yarvi.h"
`default_nettype none

module yarvi_st_align
/* Bits of signal are not used: 'funct3'[2] */
/* verilator lint_off UNUSED */
  (input  wire [    2:0] funct3
/* verilator lint_on UNUSED */
  ,input  wire [    1:0] address
  ,input  wire [`XMSB:0] writedata
  ,output reg  [    3:0] st_mask
  ,output reg  [`XMSB:0] st_data);

   always @(*) begin
     case (address[1:0])
       // An explicitly cheap aligner     v one-bit sel       v one-bit sel    v fixed
       0: st_data = {writedata[31:24], writedata[23:16], writedata[15:8], writedata[7:0]};
       1: st_data = {writedata[ 7: 0], writedata[23:16], writedata[ 7:0], writedata[7:0]}; // must be byte
       2: st_data = {writedata[15: 8], writedata[ 7: 0], writedata[15:8], writedata[7:0]}; // at most half
       3: st_data = {writedata[ 7: 0], writedata[ 7: 0], writedata[ 7:0], writedata[7:0]}; // must be byte
     endcase
     case (funct3[1:0])
       0: st_mask = 4'h1 << address[1:0];
       1: st_mask = address[1] ? 4'hC : 4'h3;
       2: st_mask = 4'hF;
       3: st_mask = 4'hX;
     endcase
   end
endmodule
