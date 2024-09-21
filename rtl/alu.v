// -----------------------------------------------------------------------
//
// A purely combinatorial RV32I ALU (assumes predecoded steering)
//
// ISC License
//
// Copyright (C) 2014 - 2022  Tommy Thorn <tommy-github2@thorn.ws>
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
// -----------------------------------------------------------------------

/* The width comparisons in Verilator are completely broken. */
/* verilator lint_off WIDTH */

`define ADDSUB          0
`define SLL             1
`define SLT             2
`define SLTU            3
`define XOR             4
`define SR_             5
`define OR              6
`define AND             7

/* The function selector of the ALU is kept close to the RISC-V ISA,
   but it assumes a lot of instructions translate their opcodes into
   the ALU appropriate ones and feed the ALU with the relevant operands.

   Further improvement possible:
   - multi-cycle shifter (eg. migrate shifter out of this ALU)
*/

`default_nettype none

module alu
  #(parameter XLEN = 64,
    parameter SHIFT_EN = 1, // Shifts might be migrated out
    parameter W_EN = XLEN == 64,
    parameter MSB = XLEN - 1)
   (input wire          sub,
    input wire          ashr,
    input wire  [ 2:0]  funct3,
    input wire          w,
    input wire  [MSB:0] op1,
    input wire  [MSB:0] op2,

    output reg  [MSB:0] result,
    output wire [MSB:0] sum,
    output wire         eq,
    output wire         lt,
    output wire         ltu);

   assign                sum = op1 + op2;
   wire [XLEN:0]         dif = op1 - op2;

   assign                eq  = op1 == op2;
   // The signed comparison is funky, but it suffice to check the MSB
   // of diff, op1, and op2.
   assign                lt  = dif[MSB] ^ (op1[MSB] != op2[MSB] && op1[MSB] != dif[MSB]);
   assign                ltu = dif[XLEN];

always @(*) begin
   // Yosys doesn't do timing based synthesis so here we manually
   // balance the cascaded mux, giving the slowest logic (the adder
   // calculation) the cheapest path through the mux
   case (funct3)
     `SLT:    result = {{MSB{1'd0}}, lt}; // $signed(op1) < $signed(op2)
     `SLTU:   result = {{MSB{1'd0}}, ltu}; // op1 < op2
     `ADDSUB: result = sub ? dif[MSB:0] : sum[MSB:0];
     default:
       case (funct3)
         // SRAW is unusual in the world of RISC in that it requires
         // sign extension of both the operand and the result
         `SR_:
	   if (SHIFT_EN)
	     if (W_EN && w)
	       result = $signed({op1[31] & ashr, op1[31:0]}) >>> op2[4:0];
             else
               result = $signed({op1[MSB] & ashr, op1}) >>> op2[$clog2(XLEN)-1:0];
	   else
	     result = 'hX;
         `SLL:
	   if (SHIFT_EN)
	     result = op1 << op2[$clog2(XLEN)-1:0];
	   else
	     result = 'hX;
         `AND:    result = op1 & op2;
         `OR:     result = op1 | op2;
         `XOR:    result = op1 ^ op2;
         default: result = 'hX;
       endcase
   endcase

   if (W_EN && w) result = {{XLEN/2{result[XLEN/2-1]}}, result[XLEN/2-1:0]};
   end
endmodule
