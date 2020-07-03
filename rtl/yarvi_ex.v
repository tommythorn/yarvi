// -----------------------------------------------------------------------
//
//   Copyright 2016,2018,2020 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is the backend of the pipeline and encompasses decodeing,
register fetch, execution, memory access, and writeback.

Probably the most erroneous, confusion, and potentially cycle-time
stealing concept is pipeline hazards.  When pipeline is steady state
without bubbles, we can compare sources with the destination of
instructions in the pipeline and life is simple.

Alas, instructions might have to be invalidated or restarted for many
reason:
 - fetch had mispredicted a branch and fed the wrong instructions.

   We need to ensure the RF isn't updated.  Do we need to worry about
   bypass?

     FE  DE  EX  ME
     add add add BEQ

   If somehow we could magically redirect in 0 cycles then we'd have

     FE  DE  EX  ME
     ADD add add add

   and thus we could have a problem.  As long as all destination
   registers are cleared before the bypass is calculated, we are fine.

 - We could be executing a load that accesses the memory from a
   preceeding store (we don't try to bypass this rare case).

     FE  DE  EX  ME
     .   .   LD  ST

   This load must be restarted.  Same bypass story as above.

 - Misaligned loads (and stores) trap, but from an invalidation POV is
   the same.

 - We we try to share the exception logic with interrupts they are
   taken in EX.


TODO:
 - The current critical path goes from
     insn30
     -> ex_wb_val       (             12.3 ns) ALU
     -> de_rs1          (15.1 - 12.3 = 2.8 ns) Bypass
     -> de_branch_taken (20.0 - 15.1 = 4.9 ns) cond-branch logic
     -> ex_restart      (22.2 - 20.0 = 2.2 ns) CTF logic

   ALU is hard to improve, but the critial path clearly say that
   taking cond branches in EX is bad.

 - Optimize bypass by calculating mux steering earlier
*************************************************************************/

/* The width comparisons in Verilator are completely broken. */
/* verilator lint_off WIDTH */

`include "yarvi.h"
`default_nettype none

module yarvi_ex
  ( input  wire             clock
  , input  wire             reset

  , input  wire             valid
  , input  wire [`VMSB:0]   pc
  , input  wire [31:0]      insn

  /* valid is a qualifier on PC/INSN and WB_RD/VAL.  Note, all four
     combinations of valid and restart can occur. */

  , output                  restart
  , output [`VMSB:0]        restart_pc

  , output reg [`VMSB:2]    code_address
  , output reg [   31:0]    code_writedata
  , output reg [    3:0]    code_writemask

  , output                  retire_valid
  , output [ 1:0]           retire_priv
  , output [`VMSB:0]        retire_pc
  , output [31:0]           retire_insn
  , output [ 4:0]           retire_rd
  , output [`XMSB:0]        retire_wb_val

  , output     [   31:0]    debug);

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
   /* Shorthand */
   wire [   11:0] csr_mip_and_mie = csr_mip & csr_mie;


   /* Instruction decoding */
   wire [    4:0]   opcode = insn`opcode;


   reg              de_valid = 0;
   reg  [`XMSB:0]   de_pc;
   reg  [   31:0]   de_insn;
   wire             de_use_rs1, de_use_rs2;
   wire [    4:0]   de_rd;
   wire [    4:0]   de_opcode = de_insn`opcode;
   reg              de_op2_imm_use;
   reg  [`XMSB:0]   de_op2_imm;

   reg              ex_valid = 0;
   reg  [`XMSB:0]   ex_pc;
   reg  [   31:0]   ex_insn;
   reg  [    1:0]   ex_priv;

   reg              ex_restart;
   reg  [`XMSB:0]   ex_restart_pc;

   reg  [    4:0]   ex_rd = 0;  // != 0 => WE. !valid => 0
   wire [`XMSB:0]   ex_wb_val;
   wire [    4:0]   ex_opcode = ex_insn`opcode;
   wire [    2:0]   ex_funct3 = ex_insn`funct3;

   reg  [`XMSB:0]   ex_rs1, ex_rs2;

   /* Updates to machine state */
   reg  [`XMSB:0]   ex_csr_mcause;
   reg  [`XMSB:0]   ex_csr_mepc;
   reg  [`XMSB:0]   ex_csr_mstatus;
   reg  [`XMSB:0]   ex_csr_mtval;

   reg  [`XMSB:0]   ex_csr_sepc;
   reg  [`XMSB:0]   ex_csr_scause;
   reg  [`XMSB:0]   ex_csr_stval;
// reg  [`XMSB:0]   ex_csr_stvec;

   reg  [   11:0]   ex_csr_mideleg;
   reg  [   11:0]   ex_csr_medeleg;

   reg [`XMSB:0]    ex_i_imm = 0;
   reg [`XMSB:0]    ex_s_imm = 0;
   reg              ex_branch_taken = 0;

   reg              ex_csr_we;
   reg [`XMSB:0]    ex_csr_val;
   reg [`XMSB:0]    ex_csr_d;

   reg              ex_trap;
   reg [    3:0]    ex_trap_cause;
   reg [`XMSB:0]    ex_trap_val;
   reg              ex_cause_intr;
   reg [    3:0]    ex_cause;
   reg              deleg;

   reg              me_valid = 0;
   reg  [`VMSB:0]   me_pc;
   reg  [   31:0]   me_insn;
   reg  [    4:0]   me_rd = 0;
   wire [`XMSB:0]   me_wb_val;
   reg              me_exc_misaligned;
   reg  [`XMSB:0]   me_exc_mtval;
   reg              me_load_hit_store;
   reg              me_timer_interrupt;
   reg              me_trap = 0;

   assign           restart       = ex_restart;
   assign           restart_pc    = ex_restart_pc;

   assign           retire_valid  = me_valid;
   assign           retire_priv   = priv;
   assign           retire_pc     = me_pc;
   assign           retire_insn   = me_insn;
   assign           retire_rd     = me_rd;
   assign           retire_wb_val = me_wb_val;
   assign           debug         = retire_wb_val;


   wire [`XMSB-12:0] sext12       = {(`XMSB-11){insn[31]}};
   wire [`XMSB-20:0] sext20       = {(`XMSB-19){insn[31]}};
   wire [`XMSB   :0] i_imm        = {sext12, insn`funct7, insn`rs2};
   wire [`XMSB   :0] sb_imm       = {sext12, insn[7], insn[30:25], insn[11:8], 1'd0};
   wire [`XMSB   :0] s_imm        = {sext12, insn`funct7, insn`rd};
   wire [`XMSB   :0] uj_imm       = {sext20, insn[19:12], insn[20], insn[30:21], 1'd0};


   always @(posedge clock) begin
      de_valid <= valid & !ex_restart;
      de_pc    <= pc;
      de_insn  <= insn;
      if (|me_rd)
         regs[me_rd] <= me_wb_val;
   end

   wire [`XMSB   :0] de_rs1_rf = regs[de_insn`rs1];
   wire [`XMSB   :0] de_rs2_rf = regs[de_insn`rs2];

   /* NB: r0 is not considered used */
   yarvi_dec_reg_usage yarvi_dec_reg_usage_inst(de_valid, de_insn, de_use_rs1, de_use_rs2, de_rd);


   wire [`XMSB-12:0] de_sext12       = {(`XMSB-11){de_insn[31]}};
   wire [`XMSB-20:0] de_sext20       = {(`XMSB-19){de_insn[31]}};
   wire [`XMSB   :0] de_i_imm        = {de_sext12, de_insn`funct7, de_insn`rs2};
   wire [`XMSB   :0] de_sb_imm       = {de_sext12, de_insn[7], de_insn[30:25], de_insn[11:8], 1'd0};
   wire [`XMSB   :0] de_s_imm        = {de_sext12, de_insn`funct7, de_insn`rd};
   wire [`XMSB   :0] de_uj_imm       = {de_sext20, de_insn[19:12], de_insn[20], de_insn[30:21], 1'd0};

   /* Result forwarding */
   // XXX first clause is to avoid forwarding from instructions targeting r0
   wire [`XMSB:0] de_rs1             = !de_use_rs1          ? de_rs1_rf :
                                       de_insn`rs1 == ex_rd ? ex_wb_val :
                                       de_insn`rs1 == me_rd ? me_wb_val : de_rs1_rf;

   wire [`XMSB:0] de_rs2             = !de_use_rs2          ? de_rs2_rf :
                                       de_insn`rs2 == ex_rd ? ex_wb_val :
                                       de_insn`rs2 == me_rd ? me_wb_val : de_rs2_rf;

   /* Conditional Branch Evaluation (this may be a timing path) */
   wire [`XMSB:0] de_rs1_val_cmp     = {de_insn`br_unsigned,`XMSB'd0} ^ de_rs1;
   wire [`XMSB:0] de_rs2_val_cmp     = {de_insn`br_unsigned,`XMSB'd0} ^ de_rs2;
   wire           de_cmp_eq          = de_rs1 == de_rs2;
   wire           de_cmp_lt          = $signed(de_rs1_val_cmp) < $signed(de_rs2_val_cmp);
   wire           de_branch_taken    = (de_insn`br_rela ? de_cmp_lt : de_cmp_eq) ^ de_insn`br_negate;

   always @(posedge clock)
     {de_op2_imm_use, de_op2_imm}
                <= opcode == `AUIPC ||
                   opcode == `LUI    ? {1'd1, insn[31:12], 12'd 0} :
                   opcode == `JALR  ||
                   opcode == `JAL    ? {1'd1, 32'd 4}              :
                   opcode == `SYSTEM ? {1'd1, 32'd 0}              :
                   opcode == `OP_IMM ||
                   opcode == `OP_IMM_32 ||
                   opcode == `LOAD   ? {1'd1, i_imm}               :
                   opcode == `STORE  ? {1'd1, s_imm}               :
                                       0;

   /* ALU, produces ex_wb_val */
   reg            ex_alu_insn30 = 0;
   always @(posedge clock)
     ex_alu_insn30 <= (de_opcode == `OP && de_insn`funct3 == `ADDSUB ||
                         ((de_opcode == `OP ||
                           de_opcode == `OP_IMM    ||
                           de_opcode == `OP_IMM_32) && de_insn`funct3 == `SR_) ?
                         de_insn[30] : 0);
   reg [2:0]      ex_alu_funct3 = 0;
   always @(posedge clock)
     ex_alu_funct3 <= (de_opcode == `OP        ||
                       de_opcode == `OP_IMM    ||
                       de_opcode == `OP_IMM_32 ? de_insn`funct3 : `ADDSUB);

   reg [`XMSB:0] ex_alu_op1, ex_alu_op2;

   always @(posedge clock)
     ex_alu_op1 <= de_opcode == `AUIPC ||
                   de_opcode == `JALR  ||
                   de_opcode == `JAL    ? de_pc   :
                   de_opcode == `LUI    ? 0       :
                   de_opcode == `SYSTEM ? csr_val :
                                          de_rs1;

   always @(posedge clock)
     ex_alu_op2 <= de_op2_imm_use ? de_op2_imm : de_rs2;

   yarvi_alu alu(ex_alu_insn30, ex_alu_funct3, ex_alu_op1, ex_alu_op2, ex_wb_val);

   /* Pipeline restart controls */
   always @(posedge clock) begin
      ex_rd <= 0;
      ex_valid <= 0;
      ex_restart <= 0;
      ex_restart_pc <= de_pc + 4;

      if (de_valid & !ex_restart) begin
         ex_rd <= de_rd;
         ex_valid <= 1;

         if (de_use_rs1 && de_insn`rs1 == ex_rd && ex_opcode == `LOAD ||
             de_use_rs2 && de_insn`rs2 == ex_rd && ex_opcode == `LOAD) begin
            // LOAD-USE bubbles (XXX frontend stalling would be cheaper)
            ex_valid <= 0;
            ex_rd <= 0;
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
                ex_restart_pc <= (de_rs1 + de_i_imm) & ~32'd1;
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
         ex_rd <= 0;
         ex_restart <= 1;
         ex_restart_pc <= me_pc;
      end

      // XXX Misaligned exceptions should be detected like all other exceptions
      if (me_exc_misaligned || ex_trap || (csr_mip_and_mie != 0 && csr_mstatus`MIE)) begin
         ex_valid <= 0;
         $display("%5d  %x:%x EXCEPTION %d %d(%d) %d", $time/10, ex_pc, ex_insn,
                  me_exc_misaligned, ex_trap, ex_trap_cause,
                  (csr_mip_and_mie != 0 && csr_mstatus`MIE));
         ex_rd <= 0;
         ex_restart <= 1;
         ex_restart_pc <= csr_mtvec;
      end
   end

   always @(posedge clock) ex_pc    <= de_pc;
   always @(posedge clock) ex_insn  <= de_insn;
   always @(posedge clock) ex_i_imm <= de_i_imm;
   always @(posedge clock) ex_s_imm <= de_s_imm;
   always @(posedge clock) ex_rs1   <= de_rs1;
   always @(posedge clock) ex_rs2   <= de_rs2;

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

   /* CSR updates */
   always @(*) begin
      // Lots of instructions needs adds and we have some freedom here
      // ARGH, need to handle conditional branches too

      ex_csr_we                         = 0;
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
        `OP_IMM, `OP, `AUIPC, `LUI: ;

        `BRANCH:
           if (ex_branch_taken && ex_restart_pc[1:0] != 0) begin // == ex_sb_imm[1], decode time
              ex_trap                   = ex_valid;
              ex_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              ex_trap_val               = ex_restart_pc;
           end

        `JALR: begin
           if (ex_restart_pc[1:0] != 0) begin // == ex_rs1[1] ^ ex_i_imm[1]
              ex_trap                   = ex_valid;
              ex_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              ex_trap_val               = ex_restart_pc;
           end
        end

        `JAL: begin
           if (ex_restart_pc[1:0] != 0) begin // == ex_uj_imm[1], decode-time
              ex_trap                   = ex_valid;
              ex_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              ex_trap_val               = ex_restart_pc;
           end
        end

        `SYSTEM: begin
           ex_csr_we                    = ex_valid;
           case (ex_funct3)
             `CSRRS:  begin ex_csr_d    = ex_csr_val |  ex_rs1; if (ex_insn`rs1 == 0) ex_csr_we = 0; end
             `CSRRC:  begin ex_csr_d    = ex_csr_val &~ ex_rs1; if (ex_insn`rs1 == 0) ex_csr_we = 0; end
             `CSRRW:  begin ex_csr_d    =               ex_rs1; end
             `CSRRSI: begin ex_csr_d    = ex_csr_val |  {27'd0, ex_insn`rs1}; end
             `CSRRCI: begin ex_csr_d    = ex_csr_val &~ {27'd0, ex_insn`rs1}; end
             `CSRRWI: begin ex_csr_d    = $unsigned(ex_insn`rs1); end
             `PRIV: begin
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

      if (me_exc_misaligned) begin
         ex_csr_mepc                    = me_pc;
         ex_csr_mstatus`MPIE            = csr_mstatus`MIE;
         ex_csr_mstatus`MIE             = 0;
         ex_csr_mstatus`MPP             = priv;
         ex_priv                        = `PRV_M;
         ex_csr_mcause                  = me_insn`opcode == `LOAD
                                          ? `CAUSE_MISALIGNED_LOAD
                                          : `CAUSE_MISALIGNED_STORE;
         ex_csr_mtval                   = me_exc_mtval;
         //$display("%5d  EX: misaligned load/store exception %x:%x", $time/10, me_pc, me_insn);
      end else if (de_use_rs1 && de_insn`rs1 == ex_rd && ex_opcode == `LOAD ||
                   de_use_rs2 && de_insn`rs2 == ex_rd && ex_opcode == `LOAD) begin
         //$display("%5d    %x: load hazard on r%1d", $time/10, pc, de_insn`rs1);
      end else if (ex_trap || csr_mip_and_mie != 0 && csr_mstatus`MIE) begin
         if (csr_mip_and_mie != 0 && csr_mstatus`MIE) begin
            // Awkward priority scheme
            ex_cause_intr               = 1;
            ex_cause                    = (csr_mip_and_mie[1] ? 1 :
                                           csr_mip_and_mie[3] ? 3 :
                                           csr_mip_and_mie[5] ? 5 :
                                           csr_mip_and_mie[7] ? 7 :
                                           csr_mip_and_mie[9] ? 9 :
                                           11);
            ex_trap_val                 = 0;
         end else begin
            ex_cause_intr               = 0;
            ex_cause                    = ex_trap_cause;
         end

         deleg = priv <= 1 && ((ex_cause_intr ? csr_mideleg : csr_medeleg) >> ex_cause) & 1'd1;

         if (deleg) begin
            ex_csr_scause[`XMSB]        = ex_cause_intr;
            ex_csr_scause[`XMSB-1:0]    = ex_cause;
            ex_csr_sepc                 = ex_pc;
            ex_csr_stval                = ex_trap_val;
            ex_csr_mstatus`SPIE         = csr_mstatus`SIE;
            ex_csr_mstatus`SIE          = 0;
            ex_csr_mstatus`SPP          = priv; // XXX SPP is one bit whose two values are USER and SUPERVISOR?
            ex_priv                     = `PRV_S;
         end else begin
            ex_csr_mcause[`XMSB]        = ex_cause_intr;
            ex_csr_mcause[`XMSB-1:0]    = ex_cause;
            ex_csr_mepc                 = ex_pc;
            ex_csr_mtval                = ex_trap_val;
            ex_csr_mstatus`MPIE         = csr_mstatus`MIE;
            ex_csr_mstatus`MIE          = 0;
            ex_csr_mstatus`MPP          = priv;
            ex_priv                     = `PRV_M;
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

   reg  [      1:0]     me_bi;
   reg  [`PMSB-2:0]     me_wi;
   reg  [     31:0]     me_address;
   reg  [      2:0]     me_funct3;
   reg                  me_address_in_mem;
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

   wire [31:0] me_memq = {mem3[me_wi],mem2[me_wi],mem1[me_wi],mem0[me_wi]};
// SOON, we just need to move the ex_address calculation up
// reg [31:0]           me_memq = 0;
// always @(posedge clock) me_memq <= {mem3[me_wi],mem2[me_wi],mem1[me_wi],mem0[me_wi]};


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
     (me_insn`opcode != `LOAD, me_address,
      me_funct3, me_bi, me_address_in_mem ? me_memq : me_rd_other,
      me_wb_val);

   /* Store path */

   wire [`XMSB:0] ex_st_data;
   wire [    3:0] ex_st_mask;

   yarvi_st_align yarvi_st_align1
     (ex_funct3, ex_address[1:0], ex_rs2, ex_st_mask, ex_st_data);

   wire                 ex_we = ex_valid && ex_opcode == `STORE && ex_address_in_mem && !ex_misaligned;
   wire [`PMSB-2:0]     ex_wi = ex_address[`PMSB:2];
   always @(posedge clock) if (ex_we & ex_st_mask[0]) mem0[ex_wi] <= ex_st_data[ 7: 0];
   always @(posedge clock) if (ex_we & ex_st_mask[1]) mem1[ex_wi] <= ex_st_data[15: 8];
   always @(posedge clock) if (ex_we & ex_st_mask[2]) mem2[ex_wi] <= ex_st_data[23:16];
   always @(posedge clock) if (ex_we & ex_st_mask[3]) mem3[ex_wi] <= ex_st_data[31:24];

   /* Memory mapped io devices (only word-wide accesses are allowed) */
   always @(posedge clock) if (reset) begin
      mtime                             <= 0;
      mtimecmp                          <= 0;
   end else begin
      mtime                             <= mtime + 1; // XXX Yes, this is terrible
      me_timer_interrupt                <= mtime > mtimecmp;

      if (ex_valid && ex_opcode == `STORE && (ex_address & 32'h4FFFFFF3) == 32'h40000000)
        case (ex_address[3:2])
          0: mtime[31:0]                <= ex_rs2;
          1: mtime[63:32]               <= ex_rs2;
          2: mtimecmp[31:0]             <= ex_rs2;
          3: mtimecmp[63:32]            <= ex_rs2;
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
     if (!reset && ex_valid && ex_opcode == `STORE & !ex_misaligned) begin
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
      if (me_exc_misaligned | me_load_hit_store | ex_trap) begin
         me_valid               <= 0;
         me_rd                  <= 0;
      end else begin
         me_valid               <= ex_valid;
         me_rd                  <= ex_valid ? ex_rd : 0;
      end
      me_pc                     <= ex_pc;
      me_insn                   <= ex_insn;
      me_we                     <= ex_we;
      me_load_hit_store         <= 0;
      me_exc_misaligned         <= 0;
      me_exc_mtval              <= ex_address;
      me_trap                   <= ex_trap;

      if (ex_valid && ex_misaligned & (ex_opcode == `LOAD || ex_opcode == `STORE)) begin
         me_exc_misaligned      <= 1;
         me_valid               <= 0;
         me_rd                  <= 0;
         $display("%5d  ME: %x misaligned load/store ex_address %x", $time/10, ex_pc, ex_address);
      end else if (ex_valid && ex_opcode == `LOAD && me_we && ex_address[31:2] == me_address[31:2]) begin
         me_load_hit_store      <= 1;
         me_valid               <= 0;
         me_rd                  <= 0;
         $display("%5d  ME: %x load-hit-store: load from address %x hit the store to ex_address %x",
                  $time/10, ex_pc, ex_address, me_address);
      end
   end

`ifdef SIMULATION
   /* Simulation-only */
   reg [31:0] i;
   reg [31:0] data[(1<<(`PMSB - 1))-1:0];
   initial begin
      $readmemh(`INIT_MEM, data);
      for (i = 0; i < (1<<(`PMSB - 1)); i = i + 1) begin
         mem0[i] = data[i][7:0];
         mem1[i] = data[i][15:8];
         mem2[i] = data[i][23:16];
         mem3[i] = data[i][31:24];
      end
      for (i = 0; i < 32; i = i + 1)
        regs[i[4:0]] = {26'd0,i[5:0]};
   end
`endif

`ifdef DISASSEMBLE
   yarvi_disass disass
     ( .clock  (clock)
     , .info   ({ex_restart, de_valid, ex_valid, me_valid})
     , .valid  (me_valid)
     , .prv    (priv)
     , .pc     (me_pc)
     , .insn   (me_insn)
     , .wb_rd  (me_rd)
     , .wb_val (me_wb_val));
`endif
endmodule
