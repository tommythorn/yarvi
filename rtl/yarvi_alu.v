// -----------------------------------------------------------------------
//
//   Copyright 2016,2018,2020 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is the purely combinatorial ALU of YARVI

*************************************************************************/

/* The width comparisons in Verilator are completely broken. */
/* verilator lint_off WIDTH */

`include "yarvi.h"

/* The function selector of the ALU is kept close to the RISC-V ISA,
   but it assumes a lot of instructions translate their opcodes into
   the ALU appropriate ones and feed the ALU with the relevant operands.

   Further simplifications possible:
   - converting both compare to subtraction
   - converting subtraction to addition with inverse + 1
   - multi-cycle shifter
*/

`default_nettype none

`define X2MSB ($clog2(`XMSB+1)-1)

module yarvi_alu(
    input  wire           insn30
  , input  wire [    2:0] funct3
  , input  wire [`XMSB:0] op1
  , input  wire [`XMSB:0] op2
  , output reg  [`XMSB:0] result
  );

always @(*)
   case (funct3)
     `ADDSUB: result = op1 + ({32{insn30}} ^ op2) + insn30;
     `SLT:    result = {`XMSB'd0, $signed(op1) < $signed(op2)}; // or flip MSB of both operands
     `SLTU:   result = {`XMSB'd0, op1 < op2};

     `SR_:    result = $signed({op1[`XMSB] & insn30, op1}) >>> op2[`X2MSB:0];
     `SLL:    result = op1 << op2[4:0]; // XXX RV64

     `AND:    result = op1 & op2;
     `OR:     result = op1 | op2;
     `XOR:    result = op1 ^ op2;
   endcase
endmodule
