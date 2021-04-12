// -----------------------------------------------------------------------
//
//   Copyright 2016,2018,2020,2021 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is the purely combinatorial ALU of YARVI

*************************************************************************/

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
   - merge compares by toggling MSB for signed compare
   - converting [both] compare to subtraction
   - multi-cycle shifter
*/

`default_nettype none

module alu(insn30, funct3, w, op1, op2, result);
   parameter XLEN = 64;
   parameter XMSB = XLEN-1;
   parameter X2MSB = ($clog2(XLEN)-1);

   input  wire           insn30;
   input  wire [    2:0] funct3;
   input  wire           w;
   input  wire [XMSB:0]  op1;
   input  wire [XMSB:0]  op2;
   output reg  [XMSB:0]  result;

always @(*) begin
   case (funct3)
     `ADDSUB: result = op1 + ({XLEN{insn30}} ^ op2) + insn30;
     `SLT:    result = {{XMSB{1'd0}}, $signed(op1) < $signed(op2)}; // or flip MSB of both operands
     `SLTU:   result = {{XMSB{1'd0}}, op1 < op2};

     `SR_:    if (XLEN != 32 && w)
                result = $signed({op1[31] & insn30, op1[31:0]}) >>> op2[4:0];
              else
                result = $signed({op1[XMSB] & insn30, op1}) >>> op2[X2MSB:0];
     `SLL:    result = op1 << op2[X2MSB:0];

     `AND:    result = op1 & op2;
     `OR:     result = op1 | op2;
     `XOR:    result = op1 ^ op2;
   endcase
   if (XLEN != 32 && w) result = {{XLEN/2{result[XLEN/2-1]}}, result[XLEN/2-1:0]};
   end
endmodule
