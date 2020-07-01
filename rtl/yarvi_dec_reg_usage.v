// -----------------------------------------------------------------------
//
//   Copyright 2020 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is the purely combinatorial usage decoder

*************************************************************************/

/* The width comparisons in Verilator are completely broken. */
/* verilator lint_off WIDTH */

`include "yarvi.h"

`default_nettype none

module yarvi_dec_reg_usage
  ( input  wire           valid
  , input  wire [   31:0] insn
  , output reg            use_rs1
  , output reg            use_rs2);

   always @(*)
     if (!valid)
       {use_rs2,use_rs1}                = 0;
     else begin
        {use_rs2,use_rs1}               = 0;
        case (insn`opcode)
          `BRANCH: {use_rs2,use_rs1}    = 3;
          `OP:     {use_rs2,use_rs1}    = 3;
          `STORE:  {use_rs2,use_rs1}    = 3;

          `OP_IMM: {use_rs2,use_rs1}    = 1;
          `LOAD:   {use_rs2,use_rs1}    = 1;
          `JALR:   {use_rs2,use_rs1}    = 1;
          `SYSTEM:
            case (insn`funct3)
              `CSRRS:  {use_rs2,use_rs1}= 1;
              `CSRRC:  {use_rs2,use_rs1}= 1;
              `CSRRW:  {use_rs2,use_rs1}= 1;
            endcase
        endcase
        if (insn`rs1 == 0) use_rs1      = 0;
        if (insn`rs2 == 0) use_rs2      = 0;
     end
endmodule
