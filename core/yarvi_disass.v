// -----------------------------------------------------------------------
//
//   Copyright 2016,2018 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

`include "yarvi.h"

module yarvi_disass( input             clock
                   , input             valid
                   , input [ 1:0]      prv
                   , input [`VMSB:0]   pc
                   , input [31:0]      insn

                   , input             we
                   , input [ 4:0]      addr
                   , input [`VMSB:0]      d);

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

   wire        disass = 0;

  always @(posedge clock)
    if (valid & disass) begin
      case (insn`opcode)
        `BRANCH:
          case (insn`funct3)
            0: $display("%05d  %x %x beq    x%1d, x%1d, 0x%x", $time, pc, insn, insn`rs1, insn`rs2, pc + sb_imm);
            1: $display("%05d  %x %x bne    x%1d, x%1d, 0x%x", $time, pc, insn, insn`rs1, insn`rs2, pc + sb_imm);
            4: $display("%05d  %x %x blt    x%1d, x%1d, 0x%x", $time, pc, insn, insn`rs1, insn`rs2, pc + sb_imm);
            5: $display("%05d  %x %x bge    x%1d, x%1d, 0x%x", $time, pc, insn, insn`rs1, insn`rs2, pc + sb_imm);
            6: $display("%05d  %x %x bltu   x%1d, x%1d, 0x%x", $time, pc, insn, insn`rs1, insn`rs2, pc + sb_imm);
            7: $display("%05d  %x %x bgeu   x%1d, x%1d, 0x%x", $time, pc, insn, insn`rs1, insn`rs2, pc + sb_imm);
          endcase

        `OP_IMM: case (insn`funct3)
                   `ADDSUB:
                     if (insn == 32 'h 00000013)
                       $display("%05d  %x %x nop", $time, pc, insn);
                     else
                       $display("%05d  %x %x addi   x%1d, x%1d, %1d", $time, pc, insn, insn`rd, insn`rs1, $signed(i_imm));
                   `SLL:    $display("%05d  %x %x slli   x%1d, x%1d, %1d", $time, pc, insn, insn`rd, insn`rs1, i_imm[5:0]);
                   `SLT:    $display("%05d  %x %x slti   x%1d, x%1d, %1d", $time, pc, insn, insn`rd, insn`rs1, $signed(i_imm));
                   `SLTU:   $display("%05d  %x %x sltui  x%1d, x%1d, %1d", $time, pc, insn, insn`rd, insn`rs1, $signed(i_imm));
                   `XOR:    $display("%05d  %x %x xori   x%1d, x%1d, %1d", $time, pc, insn, insn`rd, insn`rs1, $signed(i_imm));
                   `SR_:  if (insn[30])
                     $display("%05d  %x %x srai   x%1d, x%1d, %1d", $time, pc, insn, insn`rd, insn`rs1, i_imm[5:0]);
                   else
                     $display("%05d  %x %x srli   x%1d, x%1d, %1d", $time, pc, insn, insn`rd, insn`rs1, i_imm[5:0]);
                   `OR:     $display("%05d  %x %x ori    x%1d, x%1d, %1d", $time, pc, insn, insn`rd, insn`rs1, $signed(i_imm));
                   `AND:    $display("%05d  %x %x andi   x%1d, x%1d, %1d", $time, pc, insn, insn`rd, insn`rs1, $signed(i_imm));
                   default: $display("%05d  %x %x OP_IMM %1d", $time, pc, insn, insn`funct3);
                 endcase

        `OP: case (insn`funct3)
               `ADDSUB: if (insn[30])
                 $display("%05d  %x %x sub    x%1d, x%1d, x%1d", $time, pc, insn, insn`rd, insn`rs1, insn`rs2);
               else
                 $display("%05d  %x %x add    x%1d, x%1d, x%1d", $time, pc, insn, insn`rd, insn`rs1, insn`rs2);
               `SLL:    $display("%05d  %x %x sll    x%1d, x%1d, x%1d", $time, pc, insn, insn`rd, insn`rs1, insn`rs2);
               `SLT:    $display("%05d  %x %x slt    x%1d, x%1d, x%1d", $time, pc, insn, insn`rd, insn`rs1, insn`rs2);
               `SLTU:   $display("%05d  %x %x sltu   x%1d, x%1d, x%1d", $time, pc, insn, insn`rd, insn`rs1, insn`rs2);
               `XOR:    $display("%05d  %x %x xor    x%1d, x%1d, x%1d", $time, pc, insn, insn`rd, insn`rs1, insn`rs2);
               `SR_:  if (insn[30])
                 $display("%05d  %x %x sra    x%1d, x%1d, x%1d", $time, pc, insn, insn`rd, insn`rs1, insn`rs2);
               else
                 $display("%05d  %x %x srl    x%1d, x%1d, x%1d", $time, pc, insn, insn`rd, insn`rs1, insn`rs2);
               `OR:     $display("%05d  %x %x ori    x%1d, x%1d, x%1d", $time, pc, insn, insn`rd, insn`rs1, insn`rs2);
               `AND:    $display("%05d  %x %x and    x%1d, x%1d, x%1d", $time, pc, insn, insn`rd, insn`rs1, insn`rs2);
               default: $display("%05d  %x %x OP %1d", $time, pc, insn, insn`funct3);
             endcase

        `LUI:  $display("%05d  %x %x lui    x%1d, 0x%1x000", $time, pc, insn, insn`rd, insn[31:12]);

        `AUIPC:$display("%05d  %x %x auipc  x%1d, 0x%1x000", $time, pc, insn, insn`rd, insn[31:12]);

        `LOAD: case (insn`funct3)
                 0: $display("%05d  %x %x lb     x%1d, %1d(x%1d)", $time, pc, insn, insn`rd, $signed(i_imm), insn`rs1);
                 1: $display("%05d  %x %x lh     x%1d, %1d(x%1d)", $time, pc, insn, insn`rd, $signed(i_imm), insn`rs1);
                 2: $display("%05d  %x %x lw     x%1d, %1d(x%1d)", $time, pc, insn, insn`rd, $signed(i_imm), insn`rs1);
                 3: $display("%05d  %x %x ld     x%1d, %1d(x%1d)", $time, pc, insn, insn`rd, $signed(i_imm), insn`rs1);
                 4: $display("%05d  %x %x lbu    x%1d, %1d(x%1d)", $time, pc, insn, insn`rd, $signed(i_imm), insn`rs1);
                 5: $display("%05d  %x %x lhu    x%1d, %1d(x%1d)", $time, pc, insn, insn`rd, $signed(i_imm), insn`rs1);
                 6: $display("%05d  %x %x lwu    x%1d, %1d(x%1d)", $time, pc, insn, insn`rd, $signed(i_imm), insn`rs1);
                 default: $display("%05d  %x %x l??%1d?? x%1d, %1d(x%1d)", $time, pc, insn, insn`funct3, insn`rd, $signed(i_imm), insn`rs1);
               endcase

        `STORE: case (insn`funct3)
                  0: $display("%05d  %x %x sb     x%1d, %1d(x%1d)", $time, pc, insn, insn`rs2, $signed(s_imm), insn`rs1);
                  1: $display("%05d  %x %x sh     x%1d, %1d(x%1d)", $time, pc, insn, insn`rs2, $signed(s_imm), insn`rs1);
                  2: $display("%05d  %x %x sw     x%1d, %1d(x%1d)", $time, pc, insn, insn`rs2, $signed(s_imm), insn`rs1);
                  3: $display("%05d  %x %x sd     x%1d, %1d(x%1d)", $time, pc, insn, insn`rs2, $signed(s_imm), insn`rs1);
                  default: $display("%05d  %x %x s??%1d?? x%1d, %1d(x%1d)", $time, pc, insn, insn`funct3, insn`rs2, $signed(s_imm), insn`rs1);
                endcase

        `JAL: $display("%05d  %x %x jal    x%1d, 0x%x", $time, pc, insn, insn`rd, pc + uj_imm);
        `JALR:
          if (insn`rd == 0 && i_imm == 0 && insn`rs1 == 32)  // XXX what is the condition for ret?
            $display("%05d  %x %x ret", $time, pc, insn);
          else
            $display("%05d  %x %x jalr   x%1d, x%1d, 0x%x", $time, pc, insn, insn`rd, insn`rs1, $signed(i_imm));

        `SYSTEM:
          case (insn`funct3)
            // XXX `PRIV: these affect control-flow
            `CSRRS:  $display("%05d  %x %x csrrs  x%1d, csr%03X, x%1d", $time, pc, insn, insn`rd, insn`imm11_0, insn`rs1);
            `CSRRC:  $display("%05d  %x %x csrrc  x%1d, csr%03X, x%1d", $time, pc, insn, insn`rd, insn`imm11_0, insn`rs1);
            `CSRRW:  $display("%05d  %x %x csrrw  x%1d, csr%03X, x%1d", $time, pc, insn, insn`rd, insn`imm11_0, insn`rs1);
            `CSRRSI: $display("%05d  %x %x csrrsi x%1d, csr%03X, %1d", $time, pc, insn, insn`rd, insn`imm11_0, insn`rs1);
            `CSRRCI: $display("%05d  %x %x csrrci x%1d, csr%03X, %1d", $time, pc, insn, insn`rd, insn`imm11_0, insn`rs1);
            `CSRRWI: $display("%05d  %x %x csrrwi x%1d, csr%03X, %1d", $time, pc, insn, insn`rd, insn`imm11_0, insn`rs1);
            `PRIV: begin
               case (insn`imm11_0)
                 `ECALL:  $display("%05d  %x %x ecall", $time, pc, insn);
                 `EBREAK: $display("%05d  %x %x ebreak", $time, pc, insn);
                 `MRET:   $display("%05d  %x %x mret", $time, pc, insn);
                 default: begin
                    $display("%05d  %x %x PRIV opcode %1d?", $time, pc, insn, insn`imm11_0);
                    $finish;
                 end
               endcase
            end
          endcase

        `MISC_MEM:
          case (insn`funct3)
            `FENCE:   $display("%05d  %x %x fence", $time, pc, insn);
            `FENCE_I: $display("%05d  %x %x fence.i", $time, pc, insn);
            default: begin
               $display("%05d  %x %x unknown MISC_MEM sub %x", $time, pc, insn, insn`funct3);
               $finish;
            end
          endcase

        default: begin
           $display("%05d  %x %x ? opcode %1d", $time, pc, insn, insn`opcode);
           $finish;
        end
      endcase

       if (we)
         $display("%05d                                            x%2d <- 0x%x", $time, addr, d);
    end



  always @(posedge clock)
    if (valid & !disass)
       if (we)
         $display("%d 0x%08x (0x%x) x%2d 0x%x", prv, pc, insn, addr, d);
       else
         $display("%d 0x%08x (0x%x)", prv, pc, insn);
endmodule
