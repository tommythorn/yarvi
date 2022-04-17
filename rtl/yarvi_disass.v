// -----------------------------------------------------------------------
//
// Non-synthesizable RV32I disassembler/trace generator
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

`include "yarvi.h"

module yarvi_disass( input             clock
                   , input [ 6:0]      info
                   , input             valid
                   , input [ 1:0]      prv
                   , input [`VMSB:0]   pc
                   , input [31:0]      insn

                   , input [ 4:0]      wb_rd
                   , input [`VMSB:0]   wb_val);

`ifdef DISASSEMBLE
   wire        we            = |wb_rd;

   wire        sign          = insn[31];
   wire [19:0] sign20        = {20{sign}};
   wire [11:0] sign12        = {12{sign}};

   // I-type
   wire [`VMSB:0] i_imm        = {sign20, insn`funct7, insn`rs2};

   // S-type
   wire [`VMSB:0] s_imm        = {sign20, insn`funct7, insn`rd};
   wire [`VMSB:0] sb_imm       = {sign20, insn[7], insn[30:25], insn[11:8], 1'd0};

   // U-type
   wire [`VMSB:0] uj_imm       = {sign12, insn[19:12], insn[20], insn[30:21], 1'd0};

   wire           disass_en = 1;

   always @(posedge clock) begin
      $write("%5d", $time/10);

      if (valid && we)
        $write(" %x %x", pc, wb_val);
      else if (valid && disass_en)
        $write(" %x         ", pc);
      else
        $write("                   -"); // XXX Add bubble reason

      if (valid && disass_en) begin
         case (insn`opcode)
           `BRANCH:
             case (insn`funct3)
               0: $write(" beq    r%1d, r%1d, 0x%x", insn`rs1, insn`rs2, pc + sb_imm);
               1: $write(" bne    r%1d, r%1d, 0x%x", insn`rs1, insn`rs2, pc + sb_imm);
               4: $write(" blt    r%1d, r%1d, 0x%x", insn`rs1, insn`rs2, pc + sb_imm);
               5: $write(" bge    r%1d, r%1d, 0x%x", insn`rs1, insn`rs2, pc + sb_imm);
               6: $write(" bltu   r%1d, r%1d, 0x%x", insn`rs1, insn`rs2, pc + sb_imm);
               7: $write(" bgeu   r%1d, r%1d, 0x%x", insn`rs1, insn`rs2, pc + sb_imm);
             endcase

           `OP_IMM:
             case (insn`funct3)
               `ADDSUB:
                 if (insn == 32 'h 00000013)
                   $write(" nop");
                 else
                   $write(" addi   r%1d, r%1d, %1d", insn`rd, insn`rs1, $signed(i_imm));
               `SLL:  $write(" slli   r%1d, r%1d, %1d", insn`rd, insn`rs1, i_imm[5:0]);
               `SLT:  $write(" slti   r%1d, r%1d, %1d", insn`rd, insn`rs1, $signed(i_imm));
               `SLTU: $write(" sltui  r%1d, r%1d, %1d", insn`rd, insn`rs1, $signed(i_imm));
               `XOR:  $write(" xori   r%1d, r%1d, %1d", insn`rd, insn`rs1, $signed(i_imm));
               `SR_:  $write(" sr%si   r%1d, r%1d, %1d", insn[30] ? "a" : "l", insn`rd, insn`rs1, i_imm[5:0]);
               `OR:   $write(" ori    r%1d, r%1d, %1d", insn`rd, insn`rs1, $signed(i_imm));
               `AND:  $write(" andi   r%1d, r%1d, %1d", insn`rd, insn`rs1, $signed(i_imm));
               default:$write(" OP_IMM %1d", insn`funct3);
             endcase

           `OP:
             case (insn`funct3)
               `ADDSUB: if (insn[30])
                 $write(" sub    r%1d, r%1d, r%1d", insn`rd, insn`rs1, insn`rs2);
               else
                 $write(" add    r%1d, r%1d, r%1d", insn`rd, insn`rs1, insn`rs2);
               `SLL: $write(" sll    r%1d, r%1d, r%1d", insn`rd, insn`rs1, insn`rs2);
               `SLT: $write(" slt    r%1d, r%1d, r%1d", insn`rd, insn`rs1, insn`rs2);
               `SLTU: $write(" sltu   r%1d, r%1d, r%1d", insn`rd, insn`rs1, insn`rs2);
               `XOR: $write(" xor    r%1d, r%1d, r%1d", insn`rd, insn`rs1, insn`rs2);
               `SR_: if (insn[30])
                 $write(" sra    r%1d, r%1d, r%1d", insn`rd, insn`rs1, insn`rs2);
               else
                 $write(" srl    r%1d, r%1d, r%1d", insn`rd, insn`rs1, insn`rs2);
               `OR: $write(" ori    r%1d, r%1d, r%1d", insn`rd, insn`rs1, insn`rs2);
               `AND: $write(" and    r%1d, r%1d, r%1d", insn`rd, insn`rs1, insn`rs2);
               default: $write(" OP %1d", insn`funct3);
             endcase

           `LUI:  $write(" lui    r%1d, 0x%1x000", insn`rd, insn[31:12]);

           `AUIPC:$write(" auipc  r%1d, 0x%1x000", insn`rd, insn[31:12]);

           `LOAD:
             case (insn`funct3)
               0: $write(" lb     r%1d, %1d(r%1d)", insn`rd, $signed(i_imm), insn`rs1);
               1: $write(" lh     r%1d, %1d(r%1d)", insn`rd, $signed(i_imm), insn`rs1);
               2: $write(" lw     r%1d, %1d(r%1d)", insn`rd, $signed(i_imm), insn`rs1);
               3: $write(" ld     r%1d, %1d(r%1d)", insn`rd, $signed(i_imm), insn`rs1);
               4: $write(" lbu    r%1d, %1d(r%1d)", insn`rd, $signed(i_imm), insn`rs1);
               5: $write(" lhu    r%1d, %1d(r%1d)", insn`rd, $signed(i_imm), insn`rs1);
               6: $write(" lwu    r%1d, %1d(r%1d)", insn`rd, $signed(i_imm), insn`rs1);
               default: $write(" l??%1d?? r%1d, %1d(r%1d)", insn`funct3, insn`rd, $signed(i_imm), insn`rs1);
             endcase

           `STORE:
             case (insn`funct3)
               0: $write(" sb     r%1d, %1d(r%1d)", insn`rs2, $signed(s_imm), insn`rs1);
               1: $write(" sh     r%1d, %1d(r%1d)", insn`rs2, $signed(s_imm), insn`rs1);
               2: $write(" sw     r%1d, %1d(r%1d)", insn`rs2, $signed(s_imm), insn`rs1);
               3: $write(" sd     r%1d, %1d(r%1d)", insn`rs2, $signed(s_imm), insn`rs1);
               default: $write(" s??%1d?? r%1d, %1d(r%1d)", insn`funct3, insn`rs2, $signed(s_imm), insn`rs1);
             endcase

           `JAL: $write(" jal    r%1d, 0x%x", insn`rd, pc + uj_imm);
           `JALR:
             if (insn`rd == 0 && i_imm == 0 && insn`rs1 == 1)
               $write(" ret");
             else
               $write(" jalr   r%1d, r%1d, 0x%x", insn`rd, insn`rs1, $signed(i_imm));

           `SYSTEM:
             case (insn`funct3)
               // XXX `PRIV: these affect control-flow
               `CSRRS:  $write(" csrrs  r%1d, csr%03X, r%1d", insn`rd, insn`imm11_0, insn`rs1);
               `CSRRC:  $write(" csrrc  r%1d, csr%03X, r%1d", insn`rd, insn`imm11_0, insn`rs1);
               `CSRRW:  $write(" csrrw  r%1d, csr%03X, r%1d", insn`rd, insn`imm11_0, insn`rs1);
               `CSRRSI: $write(" csrrsi r%1d, csr%03X, %1d", insn`rd, insn`imm11_0, insn`rs1);
               `CSRRCI: $write(" csrrci r%1d, csr%03X, %1d", insn`rd, insn`imm11_0, insn`rs1);
               `CSRRWI: $write(" csrrwi r%1d, csr%03X, %1d", insn`rd, insn`imm11_0, insn`rs1);
               `PRIV: begin
                  case (insn`imm11_0)
                    `ECALL:  $write(" ecall");
                    `EBREAK: $write(" ebreak");
                    `MRET:   $write(" mret");
                    `WFI:    $write(" wfi");
                    default: begin
                       $write(" PRIV opcode %1d?", insn`imm11_0);
                       $finish;
                    end
                  endcase
               end
             endcase

           `MISC_MEM:
             case (insn`funct3)
               `FENCE:   $write(" fence");
               `FENCE_I: $write(" fence.i");
               default: begin
                  $write(" unknown MISC_MEM sub %x", insn`funct3);
                  $finish;
               end
             endcase

           default: begin
              $write(" ? opcode %1d", insn`opcode);
           end
         endcase
      end
      $write("\n");
   end
`endif
endmodule
