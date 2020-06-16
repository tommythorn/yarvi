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
               , output reg  [`XMSB:0]   ex_wb_val

               , output reg              ex_readenable
               , output reg              ex_writeenable
               , output reg  [ 2:0]      ex_funct3
               , output reg  [`XMSB:0]   ex_writedata
               );

   /* Processor architectual state is exactly this + register file and pc */
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

   // XXX some aren't use as they are virtual window on the M version
   reg  [`XMSB:0] csr_stvec;
// reg  [`XMSB:0] csr_scounteren;
// reg  [`XMSB:0] csr_sscratch;
   reg  [`XMSB:0] csr_sepc;
   reg  [`XMSB:0] csr_scause;
   reg  [`XMSB:0] csr_stval;
// reg  [`XMSB:0] csr_satp;
   wire [   11:0] csr_mip_and_mie    = csr_mip & csr_mie;


   wire        sign                  = insn[31];
   wire [`XMSB-12:0] sext12          = {(`XMSB-11){sign}};
   wire [`XMSB-20:0] sext20          = {(`XMSB-19){sign}};

   // I-type
   wire [`XMSB:0] i_imm              = {sext12, insn`funct7, insn`rs2};

   // S-type
   wire [`XMSB:0] sb_imm             = {sext12, insn[7], insn[30:25], insn[11:8], 1'd0};

   // U-type
   wire [`XMSB:0] uj_imm             = {sext20, insn[19:12], insn[20], insn[30:21], 1'd0};


   wire [`XMSB:0] rs1_val_fwd        = insn`rs1 == 0        ? 0         :
                                       insn`rs1 == ex_wb_rd ? ex_wb_val :
                                       insn`rs1 == me_wb_rd ? me_wb_val : rs1_val;

   wire [`XMSB:0] rs2_val_fwd        = insn`rs2 == 0        ? 0         :
                                       insn`rs2 == ex_wb_rd ? ex_wb_val :
                                       insn`rs2 == me_wb_rd ? me_wb_val : rs2_val;

   wire [`XMSB:0] rs1_val_cmp        = {insn`br_unsigned,`XMSB'd0} ^ rs1_val_fwd;
   wire [`XMSB:0] rs2_val_cmp        = {insn`br_unsigned,`XMSB'd0} ^ rs2_val_fwd;
   wire           cmp_eq             = rs1_val_fwd == rs2_val_fwd;
   wire           cmp_lt             = $signed(rs1_val_cmp) < $signed(rs2_val_cmp);
   wire           branch_taken       = (insn`br_rela ? cmp_lt : cmp_eq) ^ insn`br_negate;
// wire [`XMSB:0] rs2_val_imm        = (insn`opcode == `OP_IMM || insn`opcode == `OP_IMM_32
//                                      ? i_imm : rs2_val_fwd);

   always @(posedge clock) begin
      ex_valid <= 0;
      ex_restart <= 0;
      ex_restart_pc <= 'hDEADBEEF;

      if (valid & !ex_restart) begin
         ex_valid <= 1;

         if (use_rs1 && insn`rs1 == ex_wb_rd && ex_valid && ex_insn`opcode == `LOAD ||
             use_rs2 && insn`rs2 == ex_wb_rd && ex_valid && ex_insn`opcode == `LOAD) begin
            ex_restart <= 1;
            ex_restart_pc <= pc;
            ex_valid <= 0;
         end else
           case (insn`opcode)
             `BRANCH: begin
                ex_restart_pc <= pc + sb_imm;
                if (branch_taken)
                  ex_restart <= 1;
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
         ex_restart <= 1;
         ex_restart_pc <= me_pc;
         ex_valid <= 0;
         $display("    Load hit store, restarting from %x", me_pc);
      end else if (me_exc_misaligned || ex_trap || (csr_mip_and_mie != 0 && csr_mstatus`MIE)) begin
         ex_restart <= 1;
         ex_restart_pc <= csr_mtvec;
         ex_valid <= 0;
      end
   end

   wire ex_flush_this = me_exc_misaligned | me_load_hit_store;
   wire ex_flush_next = ex_restart | ex_flush_this;

`ifdef SIMULATION
   // Asserts would be nice here
   always @(posedge clock)
     if (!ex_valid && ex_wb_rd != 0) begin
        $display("assert(ex_valid || ex_wb_rd == 0) failed");
        $finish;
     end
`endif

   always @(posedge clock) ex_pc    <= pc;
   always @(posedge clock) ex_insn  <= insn;

   reg                     ex_valid_incoming = 0;
   always @(posedge clock) ex_valid_incoming <= valid & !ex_flush_next;

   reg            me_insn_opcode_load;
   always @(posedge clock) me_insn_opcode_load <= ex_insn`opcode == `LOAD; // XXX Actually only need one bit from opcode

   reg  [`XMSB:0] ex_rs1_val;
   reg  [`XMSB:0] ex_rs2_val;

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

   wire        ex_sign                  = ex_insn[31];
   wire [19:0] ex_sext12                = {20{ex_sign}};
// wire [11:0] ex_sext20                = {12{ex_sign}};

   // I-type
   wire [`XMSB:0] ex_i_imm              = {ex_sext12, ex_insn`funct7, ex_insn`rs2};

   // S-type
   wire [`XMSB:0] ex_s_imm              = {ex_sext12, ex_insn`funct7, ex_insn`rd};
// wire [`XMSB:0] ex_sb_imm             = {ex_sext12, ex_insn[7], ex_insn[30:25], ex_insn[11:8], 1'd0};

   // U-type
// wire [`XMSB:0] ex_uj_imm             = {ex_sext20, ex_insn[19:12], ex_insn[20], ex_insn[30:21], 1'd0};

   /* XXX style violation: operates directly on inputs; should be moved to decode */
   reg use_rs1, use_rs2;
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

   wire debug_bypass = 0;

   always @(posedge clock)
     if      (!use_rs1)
       ex_rs1_val <= 0;
     else if (insn`rs1 == ex_wb_rd)
       ex_rs1_val <= ex_wb_val;
     else if (insn`rs1 == me_wb_rd)
       ex_rs1_val <= me_wb_val;
     else begin
       ex_rs1_val <= rs1_val;
       if (debug_bypass)
       $display("%x: get    r%1d from RF %x",
                pc, insn`rs1, rs1_val);
     end

   always @(posedge clock)
     if      (!use_rs2)
       ex_rs2_val <= 0;
     else if (insn`rs2 == ex_wb_rd)
       ex_rs2_val <= ex_wb_val;
     else if (insn`rs2 == me_wb_rd) begin
       ex_rs2_val <= me_wb_val;
       if (debug_bypass)
       $display("%x: bypass r%1d from ME %x", pc, insn`rs2, me_wb_val);
     end
     else begin
       ex_rs2_val <= rs2_val;
       if (debug_bypass)
       $display("%x: get    r%1d from RF %x", pc, insn`rs2, rs2_val);
     end

   wire [`XMSB:0] ex_rs1                = ex_rs1_val;
   wire [`XMSB:0] ex_rs2                = ex_rs2_val;

   wire [`XMSB:0] ex_rs1_val_cmp        = {ex_insn`br_unsigned,`XMSB'd0} ^ ex_rs1;
   wire [`XMSB:0] ex_rs2_val_cmp        = {ex_insn`br_unsigned,`XMSB'd0} ^ ex_rs2;
   wire           ex_cmp_eq             = ex_rs1 == ex_rs2;
   wire           ex_cmp_lt             = $signed(ex_rs1_val_cmp) < $signed(ex_rs2_val_cmp);
   wire           ex_branch_taken       = (ex_insn`br_rela ? ex_cmp_lt : ex_cmp_eq) ^ ex_insn`br_negate;

   wire [`XMSB:0] ex_rs2_val_imm        = ex_insn`opcode == `OP_IMM || ex_insn`opcode == `OP_IMM_32 ? ex_i_imm : ex_rs2;

   // XXX for timing, we should calculate csr_val already in RF and deal with the hazards
   reg [`XMSB:0]  csr_d;
   reg [`XMSB:0]  csr_val;
   always @(*)
     case (ex_insn`imm11_0)
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

       default:           begin
                          csr_val = 0;
                          if (0 && ex_valid_incoming && ex_insn`opcode == `SYSTEM && ex_insn`funct3 != 0)
                            $display("                                                 Warning: CSR %x default to zero",
                                     ex_insn`imm11_0);
                          end
     endcase

   /* This is the main ALU, as combinational logic.  This will
      eventually be rewritten/refactored into a much denser circuit
      with enables derived in the previous stage.  For now this is
      easier to work with. */

   reg           ex_csr_we;
   reg           ex_trap;
   reg [    3:0] ex_trap_cause;
   reg [`XMSB:0] ex_trap_val;
   reg           cause_intr;
   reg [    3:0] cause;
   reg           deleg;

   always @(*) begin
      ex_csr_we                         = 0;

      ex_readenable                     = 0;
      ex_writeenable                    = 0;
      ex_writedata                      = ex_rs2_val;
      ex_funct3                         = ex_insn`funct3;
      ex_wb_rd                          = 0;
      ex_wb_val                         = 0;

      ex_priv                           = priv;
      ex_csr_mcause                     = csr_mcause;
      ex_csr_mepc                       = csr_mepc;
      ex_csr_mstatus                    = csr_mstatus;
      ex_csr_mtval                      = csr_mtval;

      ex_csr_scause                     = csr_scause;
      ex_csr_sepc                       = csr_sepc;
      ex_csr_stval                      = csr_stval;
//      ex_csr_stvec                      = csr_stvec;

      ex_csr_mideleg                    = csr_mideleg;
      ex_csr_medeleg                    = csr_medeleg;

      ex_trap                           = 0;
      ex_trap_cause			= 0;
      ex_trap_val                       = 'h X;
      csr_d                             = 'h X;

      case (ex_insn`opcode)
        `OP_IMM, `OP: begin
           ex_wb_rd                     = ex_insn`rd;
           case (ex_funct3)
             `ADDSUB: ex_wb_val         = ex_insn[30] && ex_insn`opcode == `OP
                                          ?       ex_rs1  -         ex_rs2_val_imm
                                          :       ex_rs1  +         ex_rs2_val_imm;
             `SLT:    ex_wb_val         = {31'd0,$signed(ex_rs1) < $signed(ex_rs2_val_imm)}; // or flip MSB of both operands
             `SLTU:   ex_wb_val         = {31'd0, ex_rs1  <         ex_rs2_val_imm};
             `XOR:    ex_wb_val         =         ex_rs1  ^         ex_rs2_val_imm;
             `SR_:    if (ex_insn[30])
                        ex_wb_val       = $signed(ex_rs1) >>>       ex_rs2_val_imm[4:0];
                      else
                        ex_wb_val       =         ex_rs1  >>        ex_rs2_val_imm[4:0];
             `SLL:    ex_wb_val         =         ex_rs1  <<        ex_rs2_val_imm[4:0];
             `OR:     ex_wb_val         =         ex_rs1  |         ex_rs2_val_imm;
             `AND:    ex_wb_val         =         ex_rs1  &         ex_rs2_val_imm;
             default: begin
                ex_trap                 = ex_valid;
                ex_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
                ex_trap_val             = 0;

                if (ex_valid)
                  $display("Illegal instruction %x:%x", ex_pc, ex_insn);
             end
           endcase
        end

        `BRANCH: begin
           if (ex_branch_taken) begin
              if (ex_restart_pc[1:0] != 0) begin // == ex_sb_imm[1], decode time
                 ex_trap                = ex_valid;
                 ex_trap_cause          = `CAUSE_MISALIGNED_FETCH;
                 ex_trap_val            = ex_restart_pc;
              end
           end
        end

        `AUIPC: begin
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = ex_pc + {ex_insn[31:12], 12'd0};
        end

        `LUI: begin
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = {ex_insn[31:12], 12'd0};
        end

        `JALR: begin
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = ex_pc + 4;
           if (ex_restart_pc[1:0] != 0) begin // == ex_rs1_val[1] ^ ex_i_imm[1]
              ex_wb_rd                  = 0;
              ex_trap                   = ex_valid;
              ex_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              ex_trap_val               = ex_restart_pc;
           end
        end

        `JAL: begin
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = ex_pc + 4;
           if (ex_restart_pc[1:0] != 0) begin // == ex_uj_imm[1], decode-time
              ex_wb_rd                  = 0;
              ex_trap                   = ex_valid;
              ex_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              ex_trap_val               = ex_restart_pc;
           end
        end

        `SYSTEM: begin
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = csr_val;
           ex_csr_we                    = ex_valid;
           case (ex_funct3)
             `CSRRS:  begin csr_d       = csr_val |  ex_rs1; if (ex_insn`rs1 == 0) ex_csr_we = 0; end
             `CSRRC:  begin csr_d       = csr_val &~ ex_rs1; if (ex_insn`rs1 == 0) ex_csr_we = 0; end
             `CSRRW:  begin csr_d       =            ex_rs1; end
             `CSRRSI: begin csr_d       = csr_val |  {27'd0, ex_insn`rs1}; end
             `CSRRCI: begin csr_d       = csr_val &~ {27'd0, ex_insn`rs1}; end
             `CSRRWI: begin csr_d       = $unsigned(ex_insn`rs1); end
             `PRIV: begin
                ex_wb_rd                = ex_insn`rd;
                ex_csr_we               = 0;
                case (ex_insn`imm11_0)
                  `ECALL, `EBREAK: begin
                     ex_trap            = ex_valid;
                     ex_trap_cause      = ex_insn`imm11_0 == `ECALL
                                          ? `CAUSE_USER_ECALL | $unsigned(priv)
                                          : `CAUSE_BREAKPOINT;
                     ex_trap_val        = 0;
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
                     ex_trap_val        = 0;
                     if (ex_valid)
                       $display("Illegal instruction %x:%x", ex_pc, ex_insn);
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
                  ex_trap_val           = 0;
                  if (ex_valid)
                    $display("Illegal instruction %x:%x", ex_pc, ex_insn);
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
                 ex_trap_val            = 0;
                 if (ex_valid)
                   $display("Illegal instruction %x:%x", ex_pc, ex_insn);
              end
          endcase

        `LOAD: begin
           ex_readenable                = ex_valid;
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = ex_rs1 + ex_i_imm;
           if (ex_insn == 0) begin
                ex_trap                 = ex_valid;
                ex_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
                ex_trap_val             = 0;

                if (ex_valid)
                  $display("Illegal instruction %x:%x", ex_pc, ex_insn);
           end
           case (ex_insn`funct3)
             3, 6, 7: begin
                ex_trap                 = ex_valid;
                ex_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
                ex_trap_val             = 0;

                if (ex_valid)
                  $display("Illegal instruction %x:%x", ex_pc, ex_insn);
             end
           endcase
        end

        `STORE: begin
           ex_writeenable               = ex_valid;
           ex_wb_val                    = ex_rs1 + ex_s_imm;
           case (ex_insn`funct3)
             3, 4, 5, 6, 7: begin
                ex_trap                 = ex_valid;
                ex_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
                ex_trap_val             = 0;

                if (ex_valid)
                  $display("Illegal instruction %x:%x", ex_pc, ex_insn);
             end
           endcase
        end

        default: begin
           ex_trap                      = ex_valid;
           ex_trap_cause                = `CAUSE_ILLEGAL_INSTRUCTION;
           ex_trap_val                  = 0;
           if (ex_valid)
             $display("Illegal instruction %x:%x", ex_pc, ex_insn);
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
      end else if (use_rs1 && insn`rs1 == ex_wb_rd && ex_valid && ex_insn`opcode == `LOAD ||
                   use_rs2 && insn`rs2 == ex_wb_rd && ex_valid && ex_insn`opcode == `LOAD) begin
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
         $display("%5d  EXCEPTION cause %x vector to %x",
                  $time, ex_csr_mcause, csr_mtvec);
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

      if (ex_csr_we) begin
         $display(
"                                                 CSR %x <- %x", ex_insn`imm11_0, csr_d);
         case (ex_insn`imm11_0)
           `CSR_FCSR:      {csr_frm,csr_fflags} <= csr_d[7:0];
           `CSR_FFLAGS:    csr_fflags   <= csr_d[4:0];
           `CSR_FRM:       csr_frm      <= csr_d[2:0];
           `CSR_MCAUSE:    csr_mcause   <= csr_d;
//         `CSR_MCYCLE:    csr_mcycle   <= csr_d;
           `CSR_MEPC:      csr_mepc     <= csr_d & ~3;
           `CSR_MIE:       csr_mie      <= csr_d;
//         `CSR_MINSTRET:  csr_instret  <= csr_d;
           `CSR_MIP:       csr_mip      <= csr_d & `CSR_MIP_WMASK | csr_mip & ~`CSR_MIP_WMASK;
           `CSR_MIDELEG:   csr_mideleg  <= csr_d;
           `CSR_MEDELEG:   csr_medeleg  <= csr_d;
           `CSR_MSCRATCH:  csr_mscratch <= csr_d;
           `CSR_MSTATUS:   csr_mstatus  <= csr_d & ~(15 << 13); // No FP or XS;
           `CSR_MTVEC:     csr_mtvec    <= csr_d & ~1; // We don't support vectored interrupts
           `CSR_MTVAL:     csr_mtvec    <= csr_d;

           `CSR_SCAUSE:    csr_scause   <= csr_d;
           `CSR_SEPC:      csr_sepc     <= csr_d;
           `CSR_STVEC:     csr_stvec    <= csr_d & ~1; // We don't support vectored interrupts
           `CSR_STVAL:     csr_stvec    <= csr_d;

           `CSR_PMPCFG0: ;
           `CSR_PMPADDR0: ;

           4095: ;
           default:
             $display("                                                 Warning: writing an unimplemented CSR %x", ex_insn`imm11_0);
         endcase
      end
   end
endmodule
