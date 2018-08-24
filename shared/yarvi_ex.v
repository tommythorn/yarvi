// -----------------------------------------------------------------------
//
//   Copyright 2016,2018 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a simple RISC-V RV64I implementation.

XXX Need to include CSR access permission check

*************************************************************************/

`include "yarvi.h"

module yarvi_ex( input  wire             clock

               , input  wire [`VMSB:0]   pc
               , input  wire [31:0]      insn
               , input  wire [63:0]      rs1_val
               , input  wire [63:0]      rs2_val

               , output reg              ex_restart = 1
               , output reg [`VMSB:0]    ex_restart_pc = `INIT_PC

               , output reg              ex_wben
               , output reg  [63:0]      ex_wb_val
               , output reg  [ 4:0]      ex_wb_rd

               , output reg              ex_valid
               , output reg [`VMSB:0]    ex_pc
               , output reg [31:0]       ex_insn

               // Mem interface
               , output reg              ex_mem_valid = 0
               , output reg              ex_mem_writeenable
               , output reg  [`VMSB:0]   ex_mem_address
               , output reg  [`XMSB:0]   ex_mem_writedata
               , output reg  [1:0]       ex_mem_sizelg2 // 1,2,4,8
               , output reg  [4:0]       ex_mem_readtag // ignored when writedata
               , output reg              ex_mem_readsignextend

               , input  wire             me_ready

               , input  wire             me_readdatavalid // Have read result
               , input  wire [4:0]       me_readdatatag
               , input  wire [`XMSB:0]   me_readdata); // Signextended

   reg  [ 1:0] prv              = `PRV_M; // Current priviledge level
   // CSRS

   reg         valid            = 0;
   reg         valid_           = 0;
   always @(posedge clock) valid_ <= valid;

   // URW
   reg  [ 4:0] csr_fflags       = 0;		// 001
   reg  [ 2:0] csr_frm          = 0;		// 002

   reg  [63:0] csr_stvec        = 'h 100;	// 105

`ifdef not_hard_wired_to_zero
   // MRO, Machine Information Registers
   reg  [63:0] csr_mvendorid    = 0;		// f11
   reg  [63:0] csr_marchid      = 0;		// f12
   reg  [63:0] csr_mimpid       = 0;		// f13
   reg  [63:0] csr_mhartid      = 0;		// f14
`endif
   reg  [63:0] csr_satp         = 0;		// 180

   // MRW, Machine Trap Setup
   reg  [63:0] csr_mstatus      = {2'd 3, 1'd 0};// 300
   reg  [63:0] csr_medeleg      = 0;		// 302
   reg  [63:0] csr_mideleg      = 0;		// 303
   reg  [ 7:0] csr_mie          = 0;		// 304
   reg  [63:0] csr_mtvec        = 'h 100;	// 305

   // MRW, Machine Time and Counters
   // MRW, Machine Trap Handling
   reg  [63:0] csr_mscratch     = 0;		// 340
   reg  [63:0] csr_mepc         = 0;		// 341
   reg  [63:0] csr_mcause       = 0;		// 342
   reg  [63:0] csr_mtval        = 0;		// 343
   reg  [ 7:0] csr_mip          = 0;		// 344

   // URO
   reg  [63:0] csr_mcycle       = 0;		// b00
   reg  [63:0] csr_mtime        = 0;		// b01? not used?
   reg  [63:0] csr_minstret     = 0;		// b02


   wire        sign             = insn[31];
   wire [51:0] sign52           = {52{sign}};
   wire [43:0] sign44           = {44{sign}};

   // I-type
   wire [63:0] i_imm            = {sign52, insn`funct7, insn`rs2};

   // S-type
   wire [63:0] s_imm            = {sign52, insn`funct7, insn`rd};
   wire [63:0] sb_imm           = {sign52, insn[7], insn[30:25], insn[11:8], 1'd0};

   // U-type
   wire [63:0] uj_imm           = {sign44, insn[19:12], insn[20], insn[30:21], 1'd0};

   reg  [63:0] wb_wb_val        = 0;
   reg  [ 4:0] wb_wb_rd         = 0;
   reg  [ 4:0] wb_wben          = 0;
   always @(posedge clock) wb_wb_val <= ex_wb_val;
   always @(posedge clock) wb_wb_rd  <= ex_wb_rd;
   always @(posedge clock) wb_wben   <= ex_wben;

   wire        rs1_forward_ex   = insn`rs1 == ex_wb_rd && ex_wben;
   wire        rs2_forward_ex   = insn`rs2 == ex_wb_rd && ex_wben;
   wire        rs1_forward_wb   = insn`rs1 == wb_wb_rd && wb_wben;
   wire        rs2_forward_wb   = insn`rs2 == wb_wb_rd && wb_wben;

   wire [63:0] rs1              = rs1_forward_ex ? ex_wb_val :
                                  rs1_forward_wb ? wb_wb_val : rs1_val;
   wire [63:0] rs2              = rs2_forward_ex ? ex_wb_val :
                                  rs2_forward_wb ? wb_wb_val : rs2_val;

   wire [63:0] rs1_val_cmp      = (~insn`br_unsigned << 63) ^ rs1;
   wire [63:0] rs2_val_cmp      = (~insn`br_unsigned << 63) ^ rs2;
   wire        cmp_eq           = rs1 == rs2;
   wire        cmp_lt           = rs1_val_cmp  < rs2_val_cmp;
   wire        branch_taken     = (insn`br_rela ? cmp_lt : cmp_eq) ^ insn`br_negate;

   wire [63:0] rs2_val_imm      = insn`opcode == `OP_IMM ? i_imm : rs2;

   reg [63:0]  csr_d;
   reg [11:0]  csr_addr         = ~0;

   always @(posedge clock)
     case (csr_addr)
       `CSR_FFLAGS:    csr_fflags           <= csr_d;
       `CSR_FRM:       csr_frm              <= csr_d;
       `CSR_FCSR:      {csr_frm,csr_fflags} <= csr_d;

       `CSR_MSTATUS:   csr_mstatus          <= csr_d & ~(15 << 12); // No FP or XS;
       `CSR_MEDELEG:   csr_medeleg          <= csr_d;
       `CSR_MIDELEG:   csr_mideleg          <= csr_d;
       `CSR_MIE:       csr_mie              <= csr_d;
//     `CSR_MTIMECMP:  csr_mtimecmp         <= csr_d; XXX ??

       `CSR_MSCRATCH:  csr_mscratch         <= csr_d;
       `CSR_MEPC:      csr_mepc             <= csr_d;
       `CSR_MIP:       csr_mip[3]           <= csr_d[3];
       `CSR_MTVEC:     csr_mtvec            <= csr_d;
       `CSR_STVEC:     csr_stvec            <= csr_d;
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
       `CSR_MEDELEG:      csr_val = csr_medeleg;
       `CSR_MIDELEG:      csr_val = csr_mideleg;
       `CSR_MIE:          csr_val = csr_mie;
       `CSR_MTVEC:        csr_val = csr_mtvec;
       `CSR_STVEC:        csr_val = csr_stvec;
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
      if (!valid_)
        valid <= 1;

      if (valid)
      case (insn`opcode)
        `OP_IMM, `OP: begin
           ex_wben   <= |insn`rd;
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

        `BRANCH: begin
           ex_restart_pc <= pc + sb_imm;
           if (branch_taken) begin
              ex_restart    <= 1;
              valid         <= 0;
           end
        end

        `AUIPC: begin
           ex_wben   <= |insn`rd;
           ex_wb_rd  <= insn`rd;
           ex_wb_val <= pc + {{32{insn[31]}},insn[31:12], 12'd0}; // XXX sign extended?
        end

        `JAL: begin
           ex_wben       <= |insn`rd;
           ex_wb_rd      <= insn`rd;
           ex_wb_val     <= pc + 4;
           ex_restart    <= 1;
           valid         <= 0;
           ex_restart_pc <= pc + uj_imm;
        end

        `SYSTEM: begin
           ex_wben   <= |insn`rd;
           ex_wb_rd  <= insn`rd;
           ex_wb_val <= csr_val;
           csr_addr <= insn`imm11_0;
           case (insn`funct3)
             `CSRRS:  begin csr_d <= csr_val |  rs1; if (insn`rs1 == 0) csr_addr <= ~0; end
             `CSRRC:  begin csr_d <= csr_val &~ rs1; if (insn`rs1 == 0) csr_addr <= ~0; end
             `CSRRW:  begin csr_d <=            rs1; end
             `CSRRSI: begin csr_d <= csr_val |  insn`rs1; end
             `CSRRCI: begin csr_d <= csr_val &~ insn`rs1; end
             `CSRRWI: begin csr_d <=            insn`rs1; end
             `PRIV: begin
                ex_wben <= 0;
                csr_addr <= ~0;
                ex_restart <= 1;
                valid      <= 0;
                case (insn`imm11_0)
                  `ECALL: begin
                     ex_restart_pc <= csr_mtvec;
                     // XXX Handle delegation if prv <= PRV_S
                     csr_mcause <= `CAUSE_USER_ECALL | prv;
                     csr_mepc <= pc;
                     csr_mtval <= 0;
                     csr_mstatus`MPIE <= csr_mstatus`MIE;
                     csr_mstatus`MIE <= 0;
                     csr_mstatus`MPP <= prv;
                     prv <= `PRV_S;
                  end
                  `MRET: begin
                     ex_restart_pc <= csr_mepc;
                     csr_mstatus`MIE <= csr_mstatus`MPIE;
                     csr_mstatus`MPIE <= 1;
                     prv <= csr_mstatus`MPP;
                     csr_mstatus`MPP <= `PRV_U; // ??
                  end
                  //`EBREAK: $finish; // XXX
                  default: begin
                     $display("NOT IMPLEMENTED SYSTEM.PRIV 0x%x (inst %x)",
                              insn`imm11_0, insn);
                     $finish;
                  end
                endcase
             end
             default: begin
                ex_wben <= 0;
                csr_addr <= ~0;
             end
          endcase
        end
        `MISC_MEM:
            case (insn`funct3)
              `FENCE:  ;
              `FENCE_I: begin
                 ex_restart    <= 1;
                 valid         <= 0;
                 ex_restart_pc <= pc + 4;
              end

              default: begin
                 $display("%05d  %x %x *** Unsupported", $time, pc, insn, insn`opcode);
                 $finish;
              end
          endcase

        `STORE: begin
           // Address is where?
                case (insn`funct3)
                  0: $display("%05d  %x %x sb     x%1d, %1d(x%1d)", $time, pc, insn, insn`rs2, $signed(s_imm), insn`rs1);
                  1: $display("%05d  %x %x sh     x%1d, %1d(x%1d)", $time, pc, insn, insn`rs2, $signed(s_imm), insn`rs1);
                  2: $display("%05d  %x %x sw     x%1d, %1d(x%1d)", $time, pc, insn, insn`rs2, $signed(s_imm), insn`rs1);
                  3: $display("%05d  %x %x sd     x%1d, %1d(x%1d)", $time, pc, insn, insn`rs2, $signed(s_imm), insn`rs1);
                  default: $display("%05d  %x %x s??%1d?? x%1d, %1d(x%1d)", $time, pc, insn, insn`funct3, insn`rs2, $signed(s_imm), insn`rs1);
                endcase
             $display("%05d  %x %x *** Unsupported opcode %d", $time, pc, insn, insn`opcode);
             $finish;
        end

        default:
          begin
             $display("%05d  %x %x *** Unsupported opcode %d", $time, pc, insn, insn`opcode);
             $finish;
          end
      endcase
   end

   always @(posedge clock) ex_valid <= valid;
   always @(posedge clock) ex_pc    <= pc;
   always @(posedge clock) ex_insn  <= insn;
endmodule
