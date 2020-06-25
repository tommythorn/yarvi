// -----------------------------------------------------------------------
//
//   Copyright 2016,2018,2020 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a RISC-V implementation.

XXX Need to include CSR access permission check

*************************************************************************/

/* The width comparisons in Verilator are completely broken. */
/* verilator lint_off WIDTH */

`include "yarvi.h"
`default_nettype none

module yarvi_ex( input  wire             clock
               , input  wire             reset

               , input  wire             valid
               , input  wire [`XMSB:0]   pc
               , input  wire [31:0]      insn
               , input  wire [`XMSB:0]   rs1_val
               , input  wire [`XMSB:0]   rs2_val

               , input  wire [`XMSB:0]   me_pc
               , input  wire [ 4:0]      me_wb_rd  // != 0 => WE. !valid => 0
               , input  wire [`XMSB:0]   me_wb_val
               , input  wire             me_exc_misaligned
               , input  wire [`XMSB:0]   me_exc_mtval
               , input  wire             me_load_hit_store
               , input  wire             me_timer_interrupt

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
               );

   /* Processor architectual state (excluding register file and pc) */
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

   /* Instruction decoding (migrate out) */
   wire [    4:0] opcode          = insn`opcode;

   reg use_rs1, use_rs2;
   always @(*)
     if (!valid)
       {use_rs2,use_rs1}                = 0;
     else begin
        {use_rs2,use_rs1}               = 0;
        case (opcode)
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
   wire [`XMSB-12:0] sext12          = {(`XMSB-11){insn[31]}};
   wire [`XMSB-20:0] sext20          = {(`XMSB-19){insn[31]}};
   wire [`XMSB:0] i_imm              = {sext12, insn`funct7, insn`rs2};
   wire [`XMSB:0] sb_imm             = {sext12, insn[7], insn[30:25], insn[11:8], 1'd0};
   wire [`XMSB:0] s_imm              = {sext12, insn`funct7, insn`rd};
   wire [`XMSB:0] uj_imm             = {sext20, insn[19:12], insn[20], insn[30:21], 1'd0};

   /* Result forwarding */
   wire [`XMSB:0] rs1_val_fwd        = !use_rs1             ? 0         :
                                       insn`rs1 == ex_wb_rd ? ex_wb_val :
                                       insn`rs1 == me_wb_rd ? me_wb_val : rs1_val;
   wire [`XMSB:0] rs2_val_fwd        = !use_rs2             ? 0         :
                                       insn`rs2 == ex_wb_rd ? ex_wb_val :
                                       insn`rs2 == me_wb_rd ? me_wb_val : rs2_val;

   /* Conditional Branch Evaluation (this may be a timing path) */
   wire [`XMSB:0] rs1_val_cmp        = {insn`br_unsigned,`XMSB'd0} ^ rs1_val_fwd;
   wire [`XMSB:0] rs2_val_cmp        = {insn`br_unsigned,`XMSB'd0} ^ rs2_val_fwd;
   wire           cmp_eq             = rs1_val_fwd == rs2_val_fwd;
   wire           cmp_lt             = $signed(rs1_val_cmp) < $signed(rs2_val_cmp);
   wire           branch_taken       = (insn`br_rela ? cmp_lt : cmp_eq) ^ insn`br_negate;



   /* Shorthand */
   wire [    4:0] ex_opcode          = ex_insn`opcode;
   wire [   11:0] csr_mip_and_mie    = csr_mip & csr_mie;

   /* Pipeline restart controls */
   always @(posedge clock) begin
      ex_valid <= 0;
      ex_restart <= 0;
      ex_restart_pc <= 'hDEADBEEF;

      if (valid & !ex_restart) begin
         ex_valid <= 1;

         if (use_rs1 && insn`rs1 == ex_wb_rd && ex_valid && ex_opcode == `LOAD ||
             use_rs2 && insn`rs2 == ex_wb_rd && ex_valid && ex_opcode == `LOAD) begin
            ex_valid <= 0;
            ex_restart <= 1;
            ex_restart_pc <= pc;
         end else
           case (opcode)
             `BRANCH: begin
                ex_restart <= branch_taken;
                ex_restart_pc <= pc + sb_imm;
             end
             `JALR: begin
                ex_restart <= 1;
                ex_restart_pc <= (rs1_val_fwd + i_imm) & ~32'd1;
             end

             `JAL: begin
                ex_restart <= 1;
                ex_restart_pc <= pc + uj_imm;
             end

             `SYSTEM: begin
                ex_restart <= 1;
                ex_restart_pc <= pc + 4;
                case (insn`funct3)
                  `PRIV:
                    case (insn`imm11_0)
                      `ECALL, `EBREAK: ex_restart_pc <= csr_mtvec;
                      `MRET: ex_restart_pc <= csr_mepc;
                    endcase
                endcase
             end

             `MISC_MEM:
               case (insn`funct3)
                 `FENCE_I: begin
                    ex_restart <= 1;
                    ex_restart_pc <= pc + 4;
                 end
               endcase
           endcase;
      end

      if (me_load_hit_store) begin
         ex_valid <= 0;
         ex_restart <= 1;
         ex_restart_pc <= me_pc;
         //$display("    Load hit store, restarting from %x", me_pc);
      end else if (me_exc_misaligned || ex_trap || (csr_mip_and_mie != 0 && csr_mstatus`MIE)) begin
         ex_valid <= 0;
         ex_restart <= 1;
         ex_restart_pc <= csr_mtvec;
      end
   end

   wire ex_flush_next = ex_restart | me_exc_misaligned | me_load_hit_store;

`ifdef SIMULATION
   // Asserts would be nice here
   always @(posedge clock)
     if (!ex_valid && ex_wb_rd != 0) begin
        $display("assert(ex_valid || ex_wb_rd == 0) failed");
        $finish;
     end
`endif

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
   always @(posedge clock) me_insn_opcode_load <= ex_opcode == `LOAD; // XXX only one bit from opcode

   wire debug_bypass = 0;


   always @(posedge clock) ex_pc               <= pc;
   always @(posedge clock) ex_insn             <= insn;
   always @(posedge clock) ex_i_imm            <= i_imm;
   always @(posedge clock) ex_s_imm            <= s_imm;
   always @(posedge clock) ex_rs1              <= rs1_val_fwd;
   always @(posedge clock) ex_rs2              <= rs2_val_fwd;

   /* CSR read port (Notice, this is happening in DE) */
   reg [`XMSB:0]  csr_val;
   always @(*)
     case (insn`imm11_0)
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

   /* Register bypassed ALU inputs */
   always @(posedge clock)
     ex_alu_op1 <= opcode == `AUIPC ||
                   opcode == `JALR  ||
                   opcode == `JAL    ? pc   :
                   opcode == `LUI    ? 0       :
                   opcode == `SYSTEM ? csr_val :
                                       rs1_val_fwd;

   always @(posedge clock)
     ex_alu_op2 <= opcode == `AUIPC ||
                   opcode == `LUI    ? {insn[31:12], 12'd0} :
                   opcode == `JALR  ||
                   opcode == `JAL    ? 4                       :
                   opcode == `SYSTEM ? 0                       :
                   opcode == `OP_IMM ||
                   opcode == `OP_IMM_32 ||
                   opcode == `LOAD   ? i_imm                :
                   opcode == `STORE  ? s_imm                :
                                       rs2_val_fwd;

   always @(posedge clock)
     ex_branch_taken <= branch_taken;

   reg           ex_csr_we;
   reg [`XMSB:0] ex_csr_val;
   reg [`XMSB:0] ex_csr_d;

   reg           ex_trap;
   reg [    3:0] ex_trap_cause;
   reg [`XMSB:0] ex_trap_val;
   reg           cause_intr;
   reg [    3:0] cause;
   reg           deleg;

   reg           ex_alu_insn30;
   reg [    2:0] ex_alu_funct3;
   reg [`XMSB:0] ex_alu_op1;
   reg [`XMSB:0] ex_alu_op2;

   yarvi_alu alu(ex_alu_insn30, ex_alu_funct3, ex_alu_op1, ex_alu_op2, ex_wb_val);

   always @(*) begin
      // ALU inputs
      ex_alu_insn30 = ex_opcode == `OP && ex_insn`funct3 == `ADDSUB ||
                      ((ex_opcode == `OP ||
                        ex_opcode == `OP_IMM    ||
                        ex_opcode == `OP_IMM_32) && ex_insn`funct3 == `SR_) ?
                      ex_insn[30] : 0;

      ex_alu_funct3 = ex_opcode == `OP        ||
                      ex_opcode == `OP_IMM    ||
                      ex_opcode == `OP_IMM_32 ? ex_insn`funct3 : `ADDSUB;

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

        `BRANCH: begin
           if (ex_branch_taken) begin
              if (ex_restart_pc[1:0] != 0) begin // == ex_sb_imm[1], decode time
                 ex_trap                = ex_valid;
                 ex_trap_cause          = `CAUSE_MISALIGNED_FETCH;
                 ex_trap_val            = ex_restart_pc;
              end
           end
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

                  `WFI: ;

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
              `FENCE:  ;
              `FENCE_I: begin
              end

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
      end else if (use_rs1 && insn`rs1 == ex_wb_rd && ex_valid && ex_opcode == `LOAD ||
                   use_rs2 && insn`rs2 == ex_wb_rd && ex_valid && ex_opcode == `LOAD) begin
         //$display("%5d    %x: load hazard on r%1d", $time/10, pc, insn`rs1);
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
endmodule
