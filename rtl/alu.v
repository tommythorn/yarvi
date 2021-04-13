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
   - multi-cycle shifter (eg. migrate shifter out of this ALU)
*/

`default_nettype none

module alu(sub, ashr, funct3, w, op1, op2, result);
   parameter XLEN = 64;
   parameter XMSB = XLEN-1;
   parameter X2MSB = ($clog2(XLEN)-1);

   input  wire           sub;
   input  wire           ashr;
   input  wire [    2:0] funct3;
   input  wire           w;
   input  wire [XMSB:0]  op1;
   input  wire [XMSB:0]  op2;
   output reg  [XMSB:0]  result;

   // sum = op1 + op2 or op1 - op2
   wire [XLEN:0]         sum = op1 + ({XLEN{sub}} ^ op2) + sub;
   wire                  s   = sum[XMSB];
   wire                  c   = sum[XLEN];
   wire                  v   = op1[XMSB] == !op2[XMSB] && op1[XMSB] != s;

always @(*) begin
   case (funct3)
     `SLT:    result = {{XMSB{1'd0}}, s ^ v}; // $signed(op1) < $signed(op2)
     `SLTU:   result = {{XMSB{1'd0}}, !c}; // op1 < op2

`ifndef NO_SHIFTS
     `SR_:    if (XLEN != 32 && w)
                result = $signed({op1[31] & ashr, op1[31:0]}) >>> op2[4:0];
              else
                result = $signed({op1[XMSB] & ashr, op1}) >>> op2[X2MSB:0];
     `SLL:    result = op1 << op2[X2MSB:0];
`endif

     `AND:    result = op1 & op2;
     `OR:     result = op1 | op2;
     `XOR:    result = op1 ^ op2;
     default: result = 'hX;
   endcase

   if (funct3 == `ADDSUB)
     result = sum[XMSB:0];

   if (XLEN != 32 && w) result = {{XLEN/2{result[XLEN/2-1]}}, result[XLEN/2-1:0]};
   end
endmodule
