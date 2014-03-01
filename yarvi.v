// -----------------------------------------------------------------------
//
//   Copyright 2014 Tommy Thorn - All Rights Reserved
//
//   This program is free software; you can redistribute it and/or modify
//   it under the terms of the GNU General Public License as published by
//   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
//   Bostom MA 02111-1307, USA; either version 2 of the License, or
//   (at your option) any later version; incorporated herein by reference.
//
// -----------------------------------------------------------------------

`timescale 1ns/10ps

module test();
   reg clock, reset = 1;

   always #5 clock = ~clock;

   yarvi yarvi(clock, reset);

   initial begin
      #12
      reset = 0;
   end
   initial
     clock = 1;
endmodule

`define LOAD		 0
`define LOAD_FP	         1
`define CUSTOM0		 2
`define MISC_MEM	 3
`define OP_IMM		 4
`define AUIPC		 5
`define OP_IMM_32	 6
`define EXT0		 7
`define STORE		 8
`define STORE_FP	 9
`define CUSTOM1		10
`define AMO		11
`define OP		12
`define LUI		13
`define OP_32		14
`define EXT1		15
`define MADD		16
`define MSUB		17
`define NMSUB		18
`define NMADD		19
`define OP_FP		20
`define RES1		21
`define CUSTOM2		22
`define EXT2		23
`define BRANCH		24
`define JALR		25
`define RES0		26
`define JAL		27
`define SYSTEM		28
`define RES2		29
`define CUSTOM3		30
`define EXT3		31

`define ADD		0
`define SLL		1
`define SLT		2
`define SLTU		3
`define XOR		4
`define SR_		5
`define OR		6
`define AND		7


module yarvi(input clock, input reset);

   reg [31:0] pc	= 'h 74;
   reg [31:0] regs[0:31];

   reg [31:0] inst;
   reg [31:0] res;

   always @*
     casex (pc[31:0])
        'h 74:	inst = 'h 800f8b13;
        'h 78:	inst = 'h c00f8b93;
        'h 7c:	inst = 'h 500b0c93;
        'h 80:	inst = 'h 00500a13;
        'h 84:	inst = 'h 00400a93;
        'h 88:	inst = 'h 00200893;
        'h 8c:	inst = 'h 000b8d13;
        'h 90:	inst = 'h 00100993;
        'h 94:	inst = 'h 000c8913;
        'h 98:	inst = 'h 10000c13;
        'h 9c:	inst = 'h 011b8833;
        'h a0:	inst = 'h 00084803;
        'h a4:	inst = 'h 02081063;
        'h a8:	inst = 'h 015d0833;
        'h ac:	inst = 'h 011b2023;
        'h b0:	inst = 'h 004b0b13;
        'h b4:	inst = 'h 01987863;
        'h b8:	inst = 'h 01380023;
        'h bc:	inst = 'h 01180833;
        'h c0:	inst = 'h ff286ce3;
        'h c4:	inst = 'h 00188893;
        'h c8:	inst = 'h 014a8ab3;
        'h cc:	inst = 'h 002a0a13;
        'h d0:	inst = 'h fd8896e3;
        'h d4:	inst = 'h 00008067;
        default:inst = 'h ZZZZZZZZ;
    endcase

`define MEMWORDS_LG2 16
`define MEMWORDS (1 << `MEMWORDS_LG2)
   reg [31:0] mem[0:`MEMWORDS-1];

   // R-type
   wire [ 1:0] opext	= inst[1 : 0];
   wire [ 4:0] opcode	= inst[6 : 2];
   wire [ 4:0] rd	= inst[11: 7];
   wire [ 2:0] funct3	= inst[14:12];
   wire [ 4:0] rs1	= inst[19:15];
   wire [ 4:0] rs2	= inst[24:20];
   wire [ 6:0] funct7	= inst[31:25];

   wire        sign	= inst[31];
   wire [19:0] sign20	= {20{sign}};
   wire [11:0] sign12	= {12{sign}};

   // I-type
   wire [31:0] i_imm	= {sign20, funct7, rs2};

   // S-type
   wire [31:0] s_imm	= {sign20,        funct7,      rd};
   wire [31:0] sb_imm	= {sign20, rd[0], funct7[5:0], rd[4:1], 1'd0};

   // U-type
   wire [31:0] u_imm	= {sign12,funct7,rs2,rs1,funct3};

   wire [31:0] rs1_val  = regs[rs1];
   wire [31:0] rs2_val  = regs[rs2];

   wire        br_negate  = funct3[0];
   wire        br_signed  = funct3[1];
   wire        br_rela    = funct3[2];

   wire        cmp_eq     = rs1_val == rs2_val;
   wire        cmp_lt     = ((br_signed << 31) ^ rs1_val) <  ((br_signed << 31) ^ rs2_val);
   wire        branch_taken = (br_rela ? cmp_lt : cmp_eq) ^ br_negate;

   reg  [31:0] mask, ea;

   always @(posedge clock) if (!reset) begin
          if (opcode == `BRANCH && branch_taken)
             pc <= pc + sb_imm;
          else
             pc <= pc + 4;

          case (opcode)
          `OP_IMM: case (funct3)
              `ADD: res = rs1_val + i_imm;
              endcase

          `OP: case (funct3)
              `ADD: if (inst[30])
              		res = rs1_val - rs2_val;
                    else
              		res = rs1_val + rs2_val;
              endcase

          `LOAD: begin

              // XXX We could ... make the memory 16-bit and burn two ports to handle
              // all unaligned accesses.  It would make the load alignment slightly cheaper
              // but that's offset by the less efficient use of memory.  Also, it kills the
              // for-free dual-core shared memory.

              ea      = rs1_val + i_imm;
              res     = mem[ea[14:2]] >> (ea[1:0] * 8); // XXX doesn't handle unaligned correctly
              if (ea[28:`MEMWORDS_LG2])
                 res = 'h X;
              case (funct3)
              0: res = {{24{res[ 7]}}, res[ 7:0]};
              1: res = {{16{res[15]}}, res[15:0]};
              4: res = res[ 7:0];
              5: res = res[15:0];
              endcase
          end

          `STORE: begin
              ea      = rs1_val + s_imm;
              mask    = funct3 == 0 ? 'h FF : funct3 == 1 ? 'h FFFF : 'hFFFFF;
              res     = rs2_val << (ea[1:0] * 8); // XXX doesn't handle unaligned correctly
              mask    = mask    << (ea[1:0] * 8);

              if (ea[28:`MEMWORDS_LG2]) begin
                 $display("%x is outside mapped memory (%x)", ea, ea[28:`MEMWORDS_LG2]);
                 $finish;
              end

              mem[ea[14:2]] = mem[ea[14:2]] & ~mask | res & mask;
          end
          endcase

          if (rd && opcode != `BRANCH && opcode != `STORE)
            regs[rd] <= res;

          // Debugging
          case (opcode)
          `BRANCH:
              case (funct3)
              0: $display("%x beq    r%1d, r%1d, %x", pc, rs1, rs2, pc + sb_imm);
              1: $display("%x bne    r%1d, r%1d, %x", pc, rs1, rs2, pc + sb_imm);
              4: $display("%x blt    r%1d, r%1d, %x", pc, rs1, rs2, pc + sb_imm);
              5: $display("%x bge    r%1d, r%1d, %x", pc, rs1, rs2, pc + sb_imm);
              6: $display("%x bltu   r%1d, r%1d, %x", pc, rs1, rs2, pc + sb_imm);
              7: $display("%x bgeu   r%1d, r%1d, %x", pc, rs1, rs2, pc + sb_imm);
              endcase

          `OP_IMM: case (funct3)
              `ADD: begin
              		res = rs1_val + i_imm;
                        $display("%x addi   r%1d, r%1d, %1d", pc, rd, rs1, $signed(i_imm));
                     end
              default: $display("%x OP_IMM %1d", pc, funct3);
              endcase

          `OP: case (funct3)
              `ADD: if (inst[30])
                    begin
              		res = rs1_val - rs2_val;
                        $display("%x sub    r%1d, r%1d, r%1d", pc, rd, rs1, rs2);
                     end else begin
              		res = rs1_val + rs2_val;
                        $display("%x add    r%1d, r%1d, r%1d", pc, rd, rs1, rs2);
                     end
              default: $display("%x OP %1d", pc, funct3);
              endcase

          `LOAD: case (funct3)
              0: $display("%x lb     r%1d, %1d(r%1d)", pc, rd, $signed(i_imm), rs1);
              1: $display("%x lh     r%1d, %1d(r%1d)", pc, rd, $signed(i_imm), rs1);
              2: $display("%x lw     r%1d, %1d(r%1d)", pc, rd, $signed(i_imm), rs1);
              4: $display("%x lbu    r%1d, %1d(r%1d)", pc, rd, $signed(i_imm), rs1);
              5: $display("%x lhu    r%1d, %1d(r%1d)", pc, rd, $signed(i_imm), rs1);
              default: $display("%x l??%1d?? r%1d, %1d(r%1d)", pc, funct3, rd, $signed(i_imm), rs1);
              endcase

          `STORE: case (funct3)
              0: $display("%x sb     r%1d, %1d(r%1d)", pc, rs2, $signed(s_imm), rs1);
              1: $display("%x sh     r%1d, %1d(r%1d)", pc, rs2, $signed(s_imm), rs1);
              2: $display("%x sw     r%1d, %1d(r%1d)               [%x] <- %x", pc, rs2, $signed(s_imm), rs1, ea, mem[ea[14:2]]);
              default: $display("%x s??%1d?? r%1d, %1d(r%1d)", pc, funct3, rs2, $signed(s_imm), rs1);
              endcase

          default: begin
                 $display("%x ? opcode %1d", pc, opcode);
                 $finish;
              end
          endcase

          if (rd && opcode != `BRANCH && opcode != `STORE)
            $display("                                          r%1d <- 0x%x", rd, res);
   end

   reg [31:0] i;
   initial begin
     for (i = 0; i < `MEMWORDS; i = i + 1)
       mem[i] = 0;
     pc = 'h 74;
     regs[0] = 0;
     regs[31] = 'h 20000000 + 2048 + 'h f800;
   end
endmodule

