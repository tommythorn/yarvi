// -----------------------------------------------------------------------
//
//   Copyright 2016,2018,2020 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is the backend of the pipeline and encompasses decodeing,
register fetch, execution, memory access, and writeback.

*************************************************************************/

/* The width comparisons in Verilator are completely broken. */
/* verilator lint_off WIDTH */

`include "yarvi.h"
`default_nettype none

module yarvi_ex( input  wire             clock
               , input  wire             reset

               , input  wire             valid
               , input  wire [`VMSB:0]   pc
               , input  wire [31:0]      insn

/* valid is a qualifier on PC/INSN and WB_RD/VAL.  Note, all four
   combinations of valid and restart can occur. */

               , output reg              ex_valid
               , output reg  [`XMSB:0]   ex_pc
               , output reg  [31:0]      ex_insn
               , output reg  [ 1:0]      ex_priv

               , output reg              ex_restart
               , output reg  [`XMSB:0]   ex_restart_pc

               , output reg  [ 4:0]      ex_wb_rd  // != 0 => WE. !valid => 0
               , output wire [`XMSB:0]   ex_wb_val

               , output reg              ex_readenable
               , output reg              ex_writeenable
               , output reg  [ 2:0]      ex_funct3
               , output reg  [`XMSB:0]   ex_writedata

               , output reg [`VMSB:2]    code_address
               , output reg [   31:0]    code_writedata
               , output reg [    3:0]    code_writemask
               );

   /* Processor architectual state (excluding pc) */
   reg  [`XMSB:0] regs[0:31];

   reg  [    1:0] priv;
   reg  [    4:0] csr_fflags;
   reg  [    2:0] csr_frm;
   reg  [`XMSB:0] csr_mcause;
   reg  [`XMSB:0] csr_mcycle;
   reg  [`XMSB:0] csr_mepc;
   reg  [`XMSB:0] csr_minstret;
   reg  [`XMSB:0] csr_mscratch;
   reg  [`XMSB:0] csr_mstatus;
   reg  [`XMSB:0] csr_mtval;
   reg  [`XMSB:0] csr_mtvec;
   reg  [   11:0] csr_mip;
   reg  [   11:0] csr_mie;
   reg  [   11:0] csr_mideleg;
   reg  [   11:0] csr_medeleg;
   reg  [`XMSB:0] csr_stvec;
// reg  [`XMSB:0] csr_scounteren;
// reg  [`XMSB:0] csr_sscratch;
   reg  [`XMSB:0] csr_sepc;
   reg  [`XMSB:0] csr_scause;
   reg  [`XMSB:0] csr_stval;
// reg  [`XMSB:0] csr_satp;

   reg              me_valid = 0;
   reg  [31:0]      me_pc;
   reg  [ 4:0]      me_wb_rd = 0;
   wire[`XMSB:0]    me_wb_val;
   reg              me_exc_misaligned;
   reg [`XMSB:0]    me_exc_mtval;
   reg              me_load_hit_store;
   reg              me_timer_interrupt;

   /* Instruction decoding */
   reg              de_valid = 0;
   reg  [`XMSB:0]   de_pc;
   reg  [31:0]      de_insn;
   reg  [    4:0]   de_rs1, de_rs2;

   always @(posedge clock) begin
      de_valid <= valid;
      de_pc    <= pc;
      de_insn  <= insn;
      de_rs1   <= insn`rs1;
      de_rs2   <= insn`rs2;
      if (me_valid & |me_wb_rd)
         regs[me_wb_rd] <= me_wb_val;
   end

   wire [`XMSB:0]   de_rs1_val = regs[de_rs1];
   wire [`XMSB:0]   de_rs2_val = regs[de_rs2];

   reg [31:0] i;
   initial for (i = 0; i < 32; i = i + 1) regs[i[4:0]] = {26'd0,i[5:0]};


   wire              de_use_rs1, de_use_rs2;

   /* NB: r0 is not considered used */
   yarvi_dec_reg_usage yarvi_dec_reg_usage_inst(de_valid, de_insn, de_use_rs1, de_use_rs2);

   wire [       4:0] de_opcode       = de_insn`opcode;

   wire [`XMSB-12:0] de_sext12       = {(`XMSB-11){de_insn[31]}};
   wire [`XMSB-20:0] de_sext20       = {(`XMSB-19){de_insn[31]}};
   wire [`XMSB:0] de_i_imm           = {de_sext12, de_insn`funct7, de_insn`rs2};
   wire [`XMSB:0] de_sb_imm          = {de_sext12, de_insn[7], de_insn[30:25], de_insn[11:8], 1'd0};
   wire [`XMSB:0] de_s_imm           = {de_sext12, de_insn`funct7, de_insn`rd};
   wire [`XMSB:0] de_uj_imm          = {de_sext20, de_insn[19:12], de_insn[20], de_insn[30:21], 1'd0};

   /* Result forwarding */
   // XXX first clause is to avoid forwarding from instructions targeting r0
   wire [`XMSB:0] de_rs1_val_fwd     = !de_use_rs1             ? de_rs1_val :
                                       de_insn`rs1 == ex_wb_rd ? ex_wb_val  :
                                       de_insn`rs1 == me_wb_rd ? me_wb_val  : de_rs1_val;

   wire [`XMSB:0] de_rs2_val_fwd     = !de_use_rs2             ? de_rs2_val :
                                       de_insn`rs2 == ex_wb_rd ? ex_wb_val  :
                                       de_insn`rs2 == me_wb_rd ? me_wb_val  : de_rs2_val;

   /* Conditional Branch Evaluation (this may be a timing path) */
   wire [`XMSB:0] de_rs1_val_cmp     = {de_insn`br_unsigned,`XMSB'd0} ^ de_rs1_val_fwd;
   wire [`XMSB:0] de_rs2_val_cmp     = {de_insn`br_unsigned,`XMSB'd0} ^ de_rs2_val_fwd;
   wire           de_cmp_eq          = de_rs1_val_fwd == de_rs2_val_fwd;
   wire           de_cmp_lt          = $signed(de_rs1_val_cmp) < $signed(de_rs2_val_cmp);
   wire           de_branch_taken    = (de_insn`br_rela ? de_cmp_lt : de_cmp_eq) ^ de_insn`br_negate;


   /* Shorthand */
   wire [    4:0] ex_opcode          = ex_insn`opcode;
   wire [   11:0] csr_mip_and_mie    = csr_mip & csr_mie;

   /* Pipeline restart controls */
   always @(posedge clock) begin
      ex_valid <= 0;
      ex_restart <= 0;
      ex_restart_pc <= de_pc + 4;

      if (de_valid & !ex_restart) begin
         ex_valid <= 1;

         if (de_use_rs1 && de_insn`rs1 == ex_wb_rd && ex_valid && ex_opcode == `LOAD ||
             de_use_rs2 && de_insn`rs2 == ex_wb_rd && ex_valid && ex_opcode == `LOAD) begin
            // LOAD-USE bubbles (XXX frontend stalling would be cheaper)
            ex_valid <= 0;
            ex_restart <= 1;
            ex_restart_pc <= de_pc;
         end else
           case (de_opcode)
             `BRANCH: begin
                ex_restart <= de_branch_taken;
                ex_restart_pc <= de_pc + de_sb_imm;
             end

             `JALR: begin
                ex_restart <= 1;
                ex_restart_pc <= (de_rs1_val_fwd + de_i_imm) & ~32'd1;
             end

             `JAL: begin
                ex_restart <= 1;
                ex_restart_pc <= de_pc + de_uj_imm;
             end

             `SYSTEM: begin
                ex_restart <= 1;
                case (de_insn`funct3)
                  `PRIV:
                    case (de_insn`imm11_0)
                      `ECALL, `EBREAK: ex_restart_pc <= csr_mtvec;
                      `MRET: ex_restart_pc <= csr_mepc;
                    endcase
                endcase
             end

             `MISC_MEM:
               case (de_insn`funct3)
                 `FENCE_I: ex_restart <= 1;
               endcase
           endcase;
      end

      if (me_load_hit_store) begin
         ex_valid <= 0;
         ex_restart <= 1;
         ex_restart_pc <= me_pc;
      end

      if (me_exc_misaligned || ex_trap || (csr_mip_and_mie != 0 && csr_mstatus`MIE)) begin
         ex_valid <= 0;
         ex_restart <= 1;
         ex_restart_pc <= csr_mtvec;
      end
   end

   reg  [`XMSB:0] ex_rs1;
   reg  [`XMSB:0] ex_rs2;

   /* Updates to machine state */
   reg  [`XMSB:0] ex_csr_mcause;
   reg  [`XMSB:0] ex_csr_mepc;
   reg  [`XMSB:0] ex_csr_mstatus;
   reg  [`XMSB:0] ex_csr_mtval;

   reg  [`XMSB:0] ex_csr_sepc;
   reg  [`XMSB:0] ex_csr_scause;
   reg  [`XMSB:0] ex_csr_stval;
// reg  [`XMSB:0] ex_csr_stvec;

   reg  [   11:0] ex_csr_mideleg;
   reg  [   11:0] ex_csr_medeleg;

   reg [`XMSB:0]  ex_i_imm = 0;
   reg [`XMSB:0]  ex_s_imm = 0;
   reg            ex_branch_taken = 0;

   reg            me_insn_opcode_load = 0;
   always @(posedge clock)
     me_insn_opcode_load <= ex_opcode == `LOAD;

   wire debug_bypass = 0;


   always @(posedge clock) ex_pc               <= de_pc;
   always @(posedge clock) ex_insn             <= de_insn;
   always @(posedge clock) ex_i_imm            <= de_i_imm;
   always @(posedge clock) ex_s_imm            <= de_s_imm;
   always @(posedge clock) ex_rs1              <= de_rs1_val_fwd;
   always @(posedge clock) ex_rs2              <= de_rs2_val_fwd;

   /* CSR read port (Notice, this is happening in DE) */
   reg [`XMSB:0]  csr_val;
   always @(*)
     case (de_insn`imm11_0)
       // Standard User R/W
       `CSR_FFLAGS:       csr_val = {27'd0, csr_fflags};
       `CSR_FRM:          csr_val = {29'd0, csr_frm};
       `CSR_FCSR:         csr_val = {24'd0, csr_frm, csr_fflags};

       `CSR_MSTATUS:      csr_val = csr_mstatus;
       `CSR_MISA:         csr_val = (32'd 2 << 30) | (32'd 1 << ("I"-"A"));
       `CSR_MIE:          csr_val = csr_mie;
       `CSR_MTVEC:        csr_val = csr_mtvec;

       `CSR_MSCRATCH:     csr_val = csr_mscratch;
       `CSR_MEPC:         csr_val = csr_mepc;
       `CSR_MCAUSE:       csr_val = csr_mcause;
       `CSR_MTVAL:        csr_val = csr_mtval;
       `CSR_MIP:          csr_val = csr_mip;
       `CSR_MIDELEG:      csr_val = csr_mideleg;
       `CSR_MEDELEG:      csr_val = csr_medeleg;

       `CSR_MCYCLE:       csr_val = csr_mcycle;
       `CSR_MINSTRET:     csr_val = csr_minstret;

       `CSR_PMPCFG0:      csr_val = 0;
       `CSR_PMPADDR0:     csr_val = 0;

       // Standard Machine RO
       `CSR_MVENDORID:    csr_val = `VENDORID_YARVI;
       `CSR_MARCHID:      csr_val = 0;
       `CSR_MIMPID:       csr_val = 0;
       `CSR_MHARTID:      csr_val = 0;

       `CSR_SEPC:         csr_val = csr_sepc;
       `CSR_SCAUSE:       csr_val = csr_scause;
       `CSR_STVAL:        csr_val = csr_stval;
       `CSR_STVEC:        csr_val = csr_stvec;
        default:          csr_val = 0;
     endcase

   always @(posedge clock)
     ex_branch_taken <= de_branch_taken;

   reg           ex_csr_we;
   reg [`XMSB:0] ex_csr_val;
   reg [`XMSB:0] ex_csr_d;

   reg           ex_trap;
   reg [    3:0] ex_trap_cause;
   reg [`XMSB:0] ex_trap_val;
   reg           cause_intr;
   reg [    3:0] cause;
   reg           deleg;

   /* ALU, produces ex_wb_val */
   wire ex_alu_insn30 = (ex_opcode == `OP && ex_insn`funct3 == `ADDSUB ||
                         ((ex_opcode == `OP ||
                           ex_opcode == `OP_IMM    ||
                           ex_opcode == `OP_IMM_32) && ex_insn`funct3 == `SR_) ?
                         ex_insn[30] : 0);
   wire [2:0] ex_alu_funct3 = (ex_opcode == `OP        ||
                               ex_opcode == `OP_IMM    ||
                               ex_opcode == `OP_IMM_32 ? ex_insn`funct3 : `ADDSUB);
   reg [`XMSB:0] ex_alu_op1, ex_alu_op2;

   always @(posedge clock)
     ex_alu_op1 <= de_opcode == `AUIPC ||
                   de_opcode == `JALR  ||
                   de_opcode == `JAL    ? de_pc   :
                   de_opcode == `LUI    ? 0       :
                   de_opcode == `SYSTEM ? csr_val :
                                          de_rs1_val_fwd;

   always @(posedge clock)
     ex_alu_op2 <= de_opcode == `AUIPC ||
                   de_opcode == `LUI    ? {de_insn[31:12], 12'd0} :
                   de_opcode == `JALR  ||
                   de_opcode == `JAL    ? 4                       :
                   de_opcode == `SYSTEM ? 0                       :
                   de_opcode == `OP_IMM ||
                   de_opcode == `OP_IMM_32 ||
                   de_opcode == `LOAD   ? de_i_imm                   :
                   de_opcode == `STORE  ? de_s_imm                   :
                                          de_rs2_val_fwd;

   yarvi_alu alu(ex_alu_insn30, ex_alu_funct3, ex_alu_op1, ex_alu_op2, ex_wb_val);

   /* CSR updates */
   always @(*) begin
      // Lots of instructions needs adds and we have some freedom here
      // ARGH, need to handle conditional branches too

      ex_csr_we                         = 0;

      ex_readenable                     = 0;
      ex_writeenable                    = 0;
      ex_writedata                      = ex_rs2;
      ex_funct3                         = ex_insn`funct3;
      ex_wb_rd                          = 0;

      ex_priv                           = priv;
      ex_csr_mcause                     = csr_mcause;
      ex_csr_mepc                       = csr_mepc;
      ex_csr_mstatus                    = csr_mstatus;
      ex_csr_mtval                      = csr_mtval;

      ex_csr_scause                     = csr_scause;
      ex_csr_sepc                       = csr_sepc;
      ex_csr_stval                      = csr_stval;
//    ex_csr_stvec                      = csr_stvec;

      ex_csr_mideleg                    = csr_mideleg;
      ex_csr_medeleg                    = csr_medeleg;

      ex_trap                           = 0;
      ex_trap_cause                     = 0;
      ex_trap_val                       = 0;
      ex_csr_d                          = 'h X;

      case (ex_opcode)
        `OP_IMM, `OP, `AUIPC, `LUI:
           ex_wb_rd                     = ex_insn`rd;

        `BRANCH:
           if (ex_branch_taken && ex_restart_pc[1:0] != 0) begin // == ex_sb_imm[1], decode time
              ex_trap                   = ex_valid;
              ex_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              ex_trap_val               = ex_restart_pc;
           end

        `JALR: begin
           ex_wb_rd                     = ex_insn`rd;
           if (ex_restart_pc[1:0] != 0) begin // == ex_rs1[1] ^ ex_i_imm[1]
              ex_wb_rd                  = 0;
              ex_trap                   = ex_valid;
              ex_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              ex_trap_val               = ex_restart_pc;
           end
        end

        `JAL: begin
           ex_wb_rd                     = ex_insn`rd;
           if (ex_restart_pc[1:0] != 0) begin // == ex_uj_imm[1], decode-time
              ex_wb_rd                  = 0;
              ex_trap                   = ex_valid;
              ex_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              ex_trap_val               = ex_restart_pc;
           end
        end

        `SYSTEM: begin
           ex_wb_rd                     = ex_insn`rd;
           ex_csr_we                    = ex_valid;
           case (ex_funct3)
             `CSRRS:  begin ex_csr_d    = ex_csr_val |  ex_rs1; if (ex_insn`rs1 == 0) ex_csr_we = 0; end
             `CSRRC:  begin ex_csr_d    = ex_csr_val &~ ex_rs1; if (ex_insn`rs1 == 0) ex_csr_we = 0; end
             `CSRRW:  begin ex_csr_d    =               ex_rs1; end
             `CSRRSI: begin ex_csr_d    = ex_csr_val |  {27'd0, ex_insn`rs1}; end
             `CSRRCI: begin ex_csr_d    = ex_csr_val &~ {27'd0, ex_insn`rs1}; end
             `CSRRWI: begin ex_csr_d    = $unsigned(ex_insn`rs1); end
             `PRIV: begin
                ex_wb_rd                = 0;
                ex_csr_we               = 0;
                case (ex_insn`imm11_0)
                  `ECALL, `EBREAK: begin
                     ex_trap            = ex_valid;
                     ex_trap_cause      = ex_insn`imm11_0 == `ECALL
                                          ? `CAUSE_USER_ECALL | $unsigned(priv)
                                          : `CAUSE_BREAKPOINT;
                  end

                  `MRET: if (ex_valid) begin
                     ex_csr_mstatus`MIE = csr_mstatus`MPIE;
                     ex_csr_mstatus`MPIE= 1;
                     ex_priv            = csr_mstatus`MPP;
                     ex_csr_mstatus`MPP = `PRV_U;
                  end

                  `WFI: ; // XXX Should restart and block fetch until interrupt becomes pending

                  default: begin
                     ex_trap            = ex_valid;
                     ex_trap_cause      = `CAUSE_ILLEGAL_INSTRUCTION;
                  end
                endcase
             end
           endcase

           // Trap illegal CSRs accesses (ie. CSRs without permissions)
           case (ex_funct3)
             `CSRRS, `CSRRC, `CSRRW, `CSRRSI, `CSRRCI, `CSRRWI:
               if (((ex_insn`imm11_0 & 12'hC00) == 12'hC00) && ex_csr_we || priv < ex_insn[31:30]) begin
                  ex_trap               = ex_valid;
                  ex_trap_cause         = `CAUSE_ILLEGAL_INSTRUCTION;
               end
           endcase
        end

        `MISC_MEM:
            case (ex_funct3)
              `FENCE, `FENCE_I: ;
              default: begin
                 ex_trap                = ex_valid;
                 ex_trap_cause          = `CAUSE_ILLEGAL_INSTRUCTION;
              end
          endcase

        `LOAD: begin
           ex_readenable                = ex_valid;
           ex_wb_rd                     = ex_insn`rd;
           //load_address               = ex_rs1 + ex_i_imm;
           if (ex_insn == 0) begin
                ex_trap                 = ex_valid;
                ex_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
           end
           case (ex_insn`funct3)
             3, 6, 7: begin
                ex_trap                 = ex_valid;
                ex_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
             end
           endcase
        end

        `STORE: begin
           ex_writeenable               = ex_valid;
           //store_address              = ex_rs1 + ex_s_imm;
           case (ex_insn`funct3)
             3, 4, 5, 6, 7: begin
                ex_trap                 = ex_valid;
                ex_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
             end
           endcase
        end

        default: begin
           ex_trap                      = ex_valid;
           ex_trap_cause                = `CAUSE_ILLEGAL_INSTRUCTION;
        end
      endcase


      /* Handle restart causes in this priority:
         - misaligned exception, load_hit_store
         - load_hazards
         - interrupts
         - exceptions  (will take after handling interrupt)
       */

      if (!ex_valid)
        ex_wb_rd                        = 0;


      if (me_exc_misaligned) begin
         ex_csr_mepc                    = me_pc;
         ex_csr_mstatus`MPIE            = csr_mstatus`MIE;
         ex_csr_mstatus`MIE             = 0;
         ex_csr_mstatus`MPP             = priv;
         ex_priv                        = `PRV_M;
         ex_csr_mcause                  = me_insn_opcode_load
                                          ? `CAUSE_MISALIGNED_LOAD
                                          : `CAUSE_MISALIGNED_STORE;
         ex_csr_mtval                   = me_exc_mtval;
         //$display("%5d  EX: misaligned load/store exception %x:%x", $time/10, me_pc, me_insn);
      end else if (de_use_rs1 && de_insn`rs1 == ex_wb_rd && ex_valid && ex_opcode == `LOAD ||
                   de_use_rs2 && de_insn`rs2 == ex_wb_rd && ex_valid && ex_opcode == `LOAD) begin
         //$display("%5d    %x: load hazard on r%1d", $time/10, pc, de_insn`rs1);
      end else if (ex_trap || csr_mip_and_mie != 0 && csr_mstatus`MIE) begin
         if (csr_mip_and_mie != 0 && csr_mstatus`MIE) begin
            // Awkward priority scheme
            cause_intr                  = 1;
            cause                       = (csr_mip_and_mie[1] ? 1 :
                                           csr_mip_and_mie[3] ? 3 :
                                           csr_mip_and_mie[5] ? 5 :
                                           csr_mip_and_mie[7] ? 7 :
                                           csr_mip_and_mie[9] ? 9 :
                                           11);
            ex_trap_val                 = 0;
         end else begin
            cause_intr                  = 0;
            cause                       = ex_trap_cause;
         end

         deleg = ex_priv <= 1 && ((cause_intr ? csr_mideleg : csr_medeleg) >> cause) & 1'd1;

         if (deleg) begin
            ex_csr_scause[`XMSB]           = cause_intr;
            ex_csr_scause[`XMSB-1:0]       = cause;
            ex_csr_sepc                    = ex_pc;
            ex_csr_stval                   = ex_trap_val;
            ex_csr_mstatus`SPIE            = csr_mstatus`SIE;
            ex_csr_mstatus`SIE             = 0;
            ex_csr_mstatus`SPP             = priv; // XXX SPP is one bit whose two values are USER and SUPERVISOR?
            ex_priv                        = `PRV_S;
         end else begin
            ex_csr_mcause[`XMSB]           = cause_intr;
            ex_csr_mcause[`XMSB-1:0]       = cause;
            ex_csr_mepc                    = ex_pc;
            ex_csr_mtval                   = ex_trap_val;
            ex_csr_mstatus`MPIE            = csr_mstatus`MIE;
            ex_csr_mstatus`MIE             = 0;
            ex_csr_mstatus`MPP             = priv;
            ex_priv                        = `PRV_M;
         end
      end
   end

   always @(posedge clock) if (reset) begin
      priv                              <= `PRV_M;
      csr_fflags                        <= 0;
      csr_frm                           <= 0;
      csr_mcause                        <= 0;
      csr_mcycle                        <= 0;
      csr_mepc                          <= 0;
      csr_mip                           <= 0;
      csr_mie                           <= 0;
      csr_mideleg                       <= 0;
      csr_medeleg                       <= 0;

      csr_minstret                      <= 0;
      csr_mscratch                      <= 0;
      csr_mstatus                       <= {31'd 3, 1'd 0};
      csr_mtval                         <= 0;
      csr_mtvec                         <= 0;

      csr_scause                        <= 0;
      csr_sepc                          <= 0;
      csr_stval                         <= 0;

   end else begin
      ex_csr_val                        <= csr_val;

      csr_mcycle                        <= csr_mcycle + 1;
      csr_mip[7]                        <= me_timer_interrupt;

      begin
         /* Note, there's no conflicts as, by construction, the CSR
            instructions can't fault and thus ex_XXX will hold the old
            value of the CSR */
         priv                           <= ex_priv;
         csr_mcause                     <= ex_csr_mcause;
         csr_mepc                       <= ex_csr_mepc;
         csr_mstatus                    <= ex_csr_mstatus;
         csr_mtval                      <= ex_csr_mtval;
         csr_scause                     <= ex_csr_scause;
         csr_sepc                       <= ex_csr_sepc;
         csr_stval                      <= ex_csr_stval;

         csr_mideleg                    <= ex_csr_mideleg;
         csr_medeleg                    <= ex_csr_medeleg;
      end

      /* CSR write port (notice, this happens in EX) */
      if (ex_csr_we) begin
         $display(
"                                                 CSR %x <- %x", ex_insn`imm11_0, ex_csr_d);
         case (ex_insn`imm11_0)
           `CSR_FCSR:      {csr_frm,csr_fflags} <= ex_csr_d[7:0];
           `CSR_FFLAGS:    csr_fflags   <= ex_csr_d[4:0];
           `CSR_FRM:       csr_frm      <= ex_csr_d[2:0];
           `CSR_MCAUSE:    csr_mcause   <= ex_csr_d;
//         `CSR_MCYCLE:    csr_mcycle   <= ex_csr_d;
           `CSR_MEPC:      csr_mepc     <= ex_csr_d & ~3;
           `CSR_MIE:       csr_mie      <= ex_csr_d;
//         `CSR_MINSTRET:  csr_instret  <= ex_csr_d;
           `CSR_MIP:       csr_mip      <= ex_csr_d & `CSR_MIP_WMASK | csr_mip & ~`CSR_MIP_WMASK;
           `CSR_MIDELEG:   csr_mideleg  <= ex_csr_d;
           `CSR_MEDELEG:   csr_medeleg  <= ex_csr_d;
           `CSR_MSCRATCH:  csr_mscratch <= ex_csr_d;
           `CSR_MSTATUS:   csr_mstatus  <= ex_csr_d & ~(15 << 13); // No FP or XS;
           `CSR_MTVEC:     csr_mtvec    <= ex_csr_d & ~1; // We don't support vectored interrupts
           `CSR_MTVAL:     csr_mtvec    <= ex_csr_d;

           `CSR_SCAUSE:    csr_scause   <= ex_csr_d;
           `CSR_SEPC:      csr_sepc     <= ex_csr_d;
           `CSR_STVEC:     csr_stvec    <= ex_csr_d & ~1; // We don't support vectored interrupts
           `CSR_STVAL:     csr_stvec    <= ex_csr_d;

           `CSR_PMPCFG0: ;
           `CSR_PMPADDR0: ;
           default:
             $display("                                                 Warning: writing an unimplemented CSR %x", ex_insn`imm11_0);
         endcase
      end
   end

   /* Data memory */
   reg [ 7:0] mem0[(1 << (`PMSB-1)) - 1:0];
   reg [ 7:0] mem1[(1 << (`PMSB-1)) - 1:0];
   reg [ 7:0] mem2[(1 << (`PMSB-1)) - 1:0];
   reg [ 7:0] mem3[(1 << (`PMSB-1)) - 1:0];

   reg [63:0] mtime;
   reg [63:0] mtimecmp;

   wire [31:0] ex_address = ex_wb_val;
   wire        ex_address_in_mem  = (ex_address & (-1 << (`PMSB+1))) == 32'h80000000;

   /*
    * Reads come in with full addresses which we split into
    *
    *    | high | word index | byte index |
    *
    * read the full word, align it, and sign extended it
    */

   reg                  me_re;
   reg  [      1:0]     me_bi;
   reg  [`PMSB-2:0]     me_wi;
   reg  [     31:0]     me_address;
   reg  [      2:0]     me_funct3;
   reg                  me_address_in_mem;
   always @(posedge clock) me_re         <= ex_valid & ex_readenable;
   always @(posedge clock) {me_wi,me_bi} <= ex_address[`PMSB:0];
   always @(posedge clock) me_address    <= ex_address;
   always @(posedge clock) me_funct3     <= ex_funct3;
   always @(posedge clock) me_address_in_mem <= ex_address_in_mem;

   reg                  ex_misaligned;
   always @(*)
     case (ex_funct3[1:0])
       0: ex_misaligned =  0;            // Byte
       1: ex_misaligned =  ex_address[  0]; // Half
       2: ex_misaligned = |ex_address[1:0]; // Word
       3: ex_misaligned =  1'hX;
     endcase

   /* Load path */

   wire [31:0] me_rd = {mem3[me_wi],mem2[me_wi],mem1[me_wi],mem0[me_wi]};
// SOON, we just need to move the ex_address calculation up
// reg [31:0]           me_rd = 0;
// always @(posedge clock) me_rd <= {mem3[me_wi],mem2[me_wi],mem1[me_wi],mem0[me_wi]};


   /* Memory mapped io devices (only word-wide accesses are allowed) */
   // XXX me_rd_other should be folded into the bypass load register
   // to avoid the late mux in the load path
   reg [31:0]  me_rd_other;
   always @(*)
     case (me_wi)
       0: me_rd_other = mtime[31:0]; // XXX  or uart
       1: me_rd_other = mtime[63:32];
       2: me_rd_other = mtimecmp[31:0];
       3: me_rd_other = mtimecmp[63:32];
       default:
          me_rd_other = 0;
     endcase

   yarvi_ld_align yarvi_ld_align1
     (!me_re, me_address,
      me_funct3, me_bi, me_address_in_mem ? me_rd : me_rd_other,
      me_wb_val);

   /* Store path */

   wire [`XMSB:0] ex_st_data;
   wire [    3:0] ex_st_mask;

   yarvi_st_align yarvi_st_align1
     (ex_funct3, ex_address[1:0], ex_writedata, ex_st_mask, ex_st_data);

   wire                 ex_we = ex_valid && ex_writeenable & ex_address_in_mem & !ex_misaligned;
   wire [`PMSB-2:0]     ex_wi = ex_address[`PMSB:2];
   always @(posedge clock) if (ex_we & ex_st_mask[0]) mem0[ex_wi] <= ex_st_data[ 7: 0];
   always @(posedge clock) if (ex_we & ex_st_mask[1]) mem1[ex_wi] <= ex_st_data[15: 8];
   always @(posedge clock) if (ex_we & ex_st_mask[2]) mem2[ex_wi] <= ex_st_data[23:16];
   always @(posedge clock) if (ex_we & ex_st_mask[3]) mem3[ex_wi] <= ex_st_data[31:24];

   /* Memory mapped io devices (only word-wide accesses are allowed) */
   always @(posedge clock) if (reset) begin
      mtime 				<= 0;
      mtimecmp 				<= 0;
   end else begin
      mtime 				<= mtime + 1; // XXX Yes, this is terrible
      me_timer_interrupt 		<= mtime > mtimecmp;

      if (ex_valid && ex_writeenable && (ex_address & 32'h4FFFFFF3) == 32'h40000000)
        case (ex_address[3:2])
          0: mtime[31:0]		<= ex_writedata;
          1: mtime[63:32]		<= ex_writedata;
          2: mtimecmp[31:0]		<= ex_writedata;
          3: mtimecmp[63:32]		<= ex_writedata;
        endcase
   end

   always @(posedge clock) begin
      code_address   <= ex_address[`VMSB:2];
      code_writedata <= ex_st_data;
      code_writemask <= ex_we ? ex_st_mask : 0;
   end

`ifdef TOHOST
   reg  [`VMSB  :0] dump_addr;
`endif
   always @(posedge clock)
     if (!reset && ex_valid && ex_writeenable & !ex_misaligned) begin
        if (!ex_address_in_mem)
          $display("store %x -> [%x]/%x", ex_st_data, ex_address, ex_st_mask);

`ifdef TOHOST
        if (ex_st_mask == 15 & ex_address == 'h`TOHOST) begin
           /* XXX Hack for riscv-tests */
           $display("TOHOST = %d", ex_st_data);

`ifdef BEGIN_SIGNATURE
           $display("Signature Begin");
           for (dump_addr = 'h`BEGIN_SIGNATURE; dump_addr < 'h`END_SIGNATURE; dump_addr=dump_addr+4)
              $display("%x", {mem3[dump_addr[`PMSB:2]], mem2[dump_addr[`PMSB:2]], mem1[dump_addr[`PMSB:2]], mem0[dump_addr[`PMSB:2]]});
`endif
           $finish;
        end
`endif
     end

   /* Hazard detection */

   reg me_we;
   always @(posedge clock) begin
      if (me_exc_misaligned | me_load_hit_store) begin
         me_valid 		<= 0;
         me_wb_rd		<= 0;
      end else begin
         me_valid		<= ex_valid;
         me_wb_rd		<= ex_wb_rd;
      end
      me_pc 			<= ex_pc;
      me_we 			<= ex_we;
      me_load_hit_store 	<= 0;
      me_exc_misaligned 	<= 0;
      me_exc_mtval              <= ex_address;

      if (ex_valid & ex_misaligned & (ex_readenable | ex_writeenable)) begin
         me_exc_misaligned 	<= 1;
         me_valid 		<= 0;
         me_wb_rd 		<= 0;
         $display("%5d  ME: %x misaligned load/store ex_address %x", $time/10, ex_pc, ex_address);
      end else if (ex_valid && ex_readenable && me_we && ex_address[31:2] == me_address[31:2]) begin
         me_load_hit_store 	<= 1;
         me_valid 		<= 0;
         me_wb_rd 		<= 0;
         $display("%5d  ME: %x load-hit-store: load from address %x hit the store to ex_address %x",
                  $time/10, ex_pc, ex_address, me_address);
      end
   end

`ifdef SIMULATION
   /* Simulation-only */
   reg [31:0] data[(1<<(`PMSB - 1))-1:0];
   initial begin
      $readmemh(`INIT_MEM, data);
      for (i = 0; i < (1<<(`PMSB - 1)); i = i + 1) begin
         mem0[i] = data[i][7:0];
         mem1[i] = data[i][15:8];
         mem2[i] = data[i][23:16];
         mem3[i] = data[i][31:24];
      end
   end
`endif
endmodule
