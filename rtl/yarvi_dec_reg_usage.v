// -----------------------------------------------------------------------
//
// A purely combinatorial RISC-V register use/def decoder
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

`include "yarvi.h"

`default_nettype none

module yarvi_dec_reg_usage
  ( input  wire           valid
/* Bits of signal are not used: 'insn'[31:25,1:0] */
/* verilator lint_off UNUSED */
  , input  wire [   31:0] insn
/* verilator lint_on UNUSED */
  , output reg            use_rs1
  , output reg            use_rs2
  , output reg  [    4:0] rd);

   wire [4:0] no_dest = 5'd0;
   wire [4:0] dest    = insn`rd;
   wire       unused  = 0;
   wire       used    = 1;

   always @(*) begin
      {rd,use_rs2,use_rs1}                 = {no_dest, unused, unused};
      if (valid)
        case (insn`opcode)
          `BRANCH:    {rd,use_rs2,use_rs1} = {no_dest,   used,   used};
          `STORE:     {rd,use_rs2,use_rs1} = {no_dest,   used,   used};
          `OP, `OP_32:{rd,use_rs2,use_rs1} = {   dest,   used,   used};

          `OP_IMM:    {rd,use_rs2,use_rs1} = {   dest, unused,   used};
          `OP_IMM_32: {rd,use_rs2,use_rs1} = {   dest, unused,   used};
          `JALR:      {rd,use_rs2,use_rs1} = {   dest, unused,   used};
          `LOAD:      {rd,use_rs2,use_rs1} = {   dest, unused,   used};
          `SYSTEM:
            case (insn`funct3)
              `CSRRS, `CSRRC, `CSRRW:
                      {rd,use_rs2,use_rs1} = {   dest, unused,   used};
              `CSRRSI, `CSRRCI, `CSRRWI:
                      {rd,use_rs2,use_rs1} = {   dest, unused, unused};
            endcase

          `AUIPC, `LUI, `JAL:
                      {rd,use_rs2,use_rs1} = {   dest, unused, unused};
          endcase
      if (insn`rs1 == 0) use_rs1 = 0;
      if (insn`rs2 == 0) use_rs2 = 0;
   end
endmodule
