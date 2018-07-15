// -----------------------------------------------------------------------
//
//   Copyright 2016,2018 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a simple RISC-V RV64I implementation.

*************************************************************************/

`include "yarvi.h"

module yarvi_ex( input  wire             clock

               , input  wire             valid
               , input  wire [`VMSB:0]   pc
               , input  wire [31:0]      insn
               , input  wire [63:0]      rs1_val
               , input  wire [63:0]      rs2_val

               , output reg              ex_restart = 0
               , output reg [`VMSB:0]    ex_restart_pc

               , output reg              ex_wben
               , output reg  [63:0]      ex_wb_val
               , output reg  [ 4:0]      ex_wb_rd

               , output reg              ex_valid
               , output reg [`VMSB:0]    ex_pc
               , output reg [31:0]       ex_insn);

   // CSRS

   // URW
   reg  [ 4:0] csr_fflags       = 0;
   reg  [ 2:0] csr_frm          = 0;

`ifdef not_used
   // MRO, Machine Information Registers
   reg  [63:0] csr_mvendorid    = 0;
   reg  [63:0] csr_marchid      = 0;
   reg  [63:0] csr_mimpid       = 0;
   reg  [63:0] csr_mhartid      = 0;
`endif

   // MRW, Machine Trap Setup
   reg  [63:0] csr_mstatus      = {2'd 3, 1'd 0};
   reg  [ 7:0] csr_mie          = 0;
   reg  [63:0] csr_mtvec        = 'h 100;
   reg  [63:0] csr_satp         = 0;

   // MRW, Machine Time and Counters
   // MRW, Machine Trap Handling
   reg  [63:0] csr_mscratch     = 0;
   reg  [63:0] csr_mepc         = 0;
   reg  [63:0] csr_mcause       = 0;
   reg  [63:0] csr_mtval        = 0;
   reg  [ 7:0] csr_mip          = 0;

   // URO
   reg  [63:0] csr_mcycle       = 0;
   reg  [63:0] csr_mtime        = 0;
   reg  [63:0] csr_minstret     = 0;


   wire        sign         = insn[31];
   wire [51:0] sign52       = {52{sign}};
   wire [43:0] sign44       = {44{sign}};

   // I-type
   wire [63:0] i_imm        = {sign52, insn`funct7, insn`rs2};

   // S-type
   wire [63:0] s_imm        = {sign52, insn`funct7, insn`rd};
   wire [63:0] sb_imm       = {sign52, insn[7], insn[30:25], insn[11:8], 1'd0};

   // U-type
   wire [63:0] uj_imm       = {sign44, insn[19:12], insn[20], insn[30:21], 1'd0};

   wire        rs1_forward_ex = insn`rs1 == ex_insn`rd && ex_wben;
   wire        rs2_forward_ex = insn`rs2 == ex_insn`rd && ex_wben;
   wire        rs1_forward_wb = 0; // insn`rs1 == wb_insn`rd && wb_wben;
   wire        rs2_forward_wb = 0; // insn`rs2 == wb_insn`rd && wb_wben;

   wire [63:0] wb_wb_val = 0;

   wire [63:0] rs1          = rs1_forward_ex ? ex_wb_val :
                              rs1_forward_wb ? wb_wb_val : rs1_val;
   wire [63:0] rs2          = rs2_forward_ex ? ex_wb_val :
                              rs2_forward_wb ? wb_wb_val : rs2_val;

   wire [63:0] rs1_val_cmp  = (~insn`br_unsigned << 63) ^ rs1;
   wire [63:0] rs2_val_cmp  = (~insn`br_unsigned << 63) ^ rs2;
   wire        cmp_eq       = rs1 == rs2;
   wire        cmp_lt       = rs1_val_cmp  < rs2_val_cmp;
   wire        branch_taken = (insn`br_rela ? cmp_lt : cmp_eq) ^ insn`br_negate;

   wire [63:0] rs2_val_imm  = insn`opcode == `OP_IMM ? i_imm : rs2;

   reg [63:0]  csr_d;
   reg [11:0]  csr_addr = ~0;

   always @(posedge clock)
     case (csr_addr)
       `CSR_FFLAGS:    csr_fflags           <= csr_d;
       `CSR_FRM:       csr_frm              <= csr_d;
       `CSR_FCSR:      {csr_frm,csr_fflags} <= csr_d;

       `CSR_MSTATUS:   csr_mstatus          <= csr_d & ~(15 << 12); // No FP or XS;
       `CSR_MIE:       csr_mie              <= csr_d;
//     `CSR_MTIMECMP:  csr_mtimecmp         <= csr_d; XXX ??

       `CSR_MSCRATCH:  csr_mscratch         <= csr_d;
       `CSR_MEPC:      csr_mepc             <= csr_d;
       `CSR_MIP:       csr_mip[3]           <= csr_d[3];
       `CSR_MTVEC:     csr_mtvec            <= csr_d;
       `CSR_SATP:      csr_satp             <= csr_d;

       4095: ;
       default:
         $display("                                                 Warning: writing an unimplemented CSR %x", csr_addr);
     endcase

   reg [63:0]  csr_val;
   always @(*)
     case (insn`imm11_0)
       `CSR_MSTATUS:      csr_val = csr_mstatus;
       `CSR_MISA:         csr_val = (2 << 30) | (1 << ("I"-"A"));
       `CSR_MIE:          csr_val = csr_mie;
       `CSR_MTVEC:        csr_val = csr_mtvec;
       `CSR_SATP:         csr_val = csr_satp;

       `CSR_MSCRATCH:     csr_val = csr_mscratch;
       `CSR_MEPC:         csr_val = csr_mepc;
       `CSR_MCAUSE:       csr_val = csr_mcause;
       `CSR_MTVAL:        csr_val = csr_mtval;
       `CSR_MIP:          csr_val = csr_mip;

       `CSR_MCYCLE:       csr_val = csr_mcycle;
       `CSR_MINSTRET:     csr_val = csr_minstret;

       `CSR_FFLAGS:       csr_val = csr_fflags;
       `CSR_FRM:          csr_val = csr_frm;
       `CSR_FCSR:         csr_val = {csr_frm, csr_fflags};
       default:           begin
                          csr_val = 0;
                          if (valid && insn`opcode == `SYSTEM)
                            $display("                                                 Warning: CSR %x default to zero", insn`imm11_0);
                          end
     endcase

/*
   always @(posedge clock) if (valid && rs1_forward_ex)
     $display("%05d  %8x *** Forwarding rs1 (%x) from EX", $time, pc, ex_wb_val);
   always @(posedge clock) if (valid && rs2_forward_ex)
     $display("%05d  %8x *** Forwarding rs2 (%x) from EX", $time, pc, ex_wb_val);
*/

   always @(posedge clock) begin
      ex_restart <= 0;
      csr_addr <= ~0;

      case (insn`opcode)
        `OP_IMM, `OP: begin
           ex_wben   <= |insn`rd & valid;
           ex_wb_rd  <= insn`rd;
           case (insn`funct3)
             `ADDSUB: if (insn[30] && insn`opcode == `OP)
               ex_wb_val <= rs1 - rs2_val_imm;
             else
               ex_wb_val <= rs1 + rs2_val_imm;
             `SLL:  ex_wb_val <= rs1 << rs2_val_imm[4:0];
             `SLT:  ex_wb_val <= $signed(rs1) < $signed(rs2_val_imm); // flip MSB of both operands
             `SLTU: ex_wb_val <= rs1 < rs2_val_imm;
             `XOR:  ex_wb_val <= rs1 ^ rs2_val_imm;
             `SR_:  if (insn[30])
               ex_wb_val <= $signed(rs1) >>> rs2_val_imm[4:0];
             else
               ex_wb_val <= rs1 >> rs2_val_imm[4:0];
             `OR:   ex_wb_val <= rs1 | rs2_val_imm;
             `AND:  ex_wb_val <= rs1 & rs2_val_imm;
             default: ex_wben <= 0;
           endcase
        end

        `BRANCH:
          if (branch_taken) begin
             ex_restart    <= valid;
             ex_restart_pc <= pc + sb_imm;
          end

        `AUIPC: begin
           ex_wben   <= |insn`rd & valid;
           ex_wb_rd  <= insn`rd;
           ex_wb_val <= pc + {{32{insn[31]}},insn[31:12], 12'd0}; // XXX sign extended?
        end

        `JAL: begin
           ex_wben       <= |insn`rd & valid;
           ex_wb_rd      <= insn`rd;
           ex_wb_val     <= pc + 4;
           ex_restart    <= valid;
           ex_restart_pc <= pc + uj_imm;
        end

        `SYSTEM: begin
           ex_wben   <= |insn`rd & valid;
           ex_wb_rd  <= insn`rd;
           ex_wb_val <= csr_val;
           if (valid) csr_addr <= insn`imm11_0;
           case (insn`funct3)
             `CSRRS:  csr_d <= csr_val |  rs1;
             `CSRRC:  csr_d <= csr_val &~ rs1;
             `CSRRW:  csr_d <=            rs1;
             `CSRRSI: csr_d <= csr_val |  insn`rs1;
             `CSRRCI: csr_d <= csr_val &~ insn`rs1;
             `CSRRWI: csr_d <=            insn`rs1;
             default: begin
                ex_wben <= 0;
                csr_addr <= ~0;
             end
          endcase
        end
        default:
          if (valid) begin
             $display("%05d  %x %x *** Unsupported opcode %d", $time, pc, insn, insn`opcode);
            $finish;
        end
      endcase
   end

   always @(posedge clock) ex_valid <= valid;
   always @(posedge clock) ex_pc    <= pc;
   always @(posedge clock) ex_insn  <= insn;
endmodule
