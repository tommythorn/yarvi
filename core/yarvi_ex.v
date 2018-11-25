// -----------------------------------------------------------------------
//
//   Copyright 2016,2018 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a simple RISC-V RV32I implementation.

XXX Need to include CSR access permission check

*************************************************************************/

`include "yarvi.h"

module yarvi_ex( input  wire             clock
               , input  wire             reset

               , input  wire [`VMSB:0]   pc
               , input  wire [31:0]      insn
               , input  wire [`VMSB:0]   rs1_val
               , input  wire [`VMSB:0]   rs2_val

               , input  wire             me_valid
               , input  wire [ 4:0]      me_wb_rd  // != 0 => WE. !valid => 0
               , input  wire [31:0]      me_wb_val

               , output reg              ex_valid
               , output reg [`VMSB:0]    ex_pc
               , output reg [31:0]       ex_insn
               , output reg [ 1:0]       ex_priv

               , output reg              ex_restart
               , output reg [`VMSB:0]    ex_restart_pc

               , output reg  [ 4:0]      ex_wb_rd  // != 0 => WE. !valid => 0
               , output reg  [`VMSB:0]   ex_wb_val

               , output reg              ex_readenable
               , output reg              ex_writeenable
               , output reg  [ 2:0]      ex_funct3
               , output reg  [`XMSB:0]   ex_writedata
               );

   // Asserts would be nice here
   always @(posedge clock)
     if (!ex_valid && ex_wb_rd != 0) begin
        $display("assert(ex_valid || ex_wb_rd == 0) failed");
        $finish;
     end

   /* We register all inputs, so ex_??? are inputs to EX after flops
      (this isn't the most natual way to write it but matches how we
      typically draw the pipelines).  */
   reg rf_valid;
   always @(posedge clock) ex_pc      <= pc;
   always @(posedge clock) ex_insn    <= insn;
   always @(posedge clock) rf_valid   <= !ex_restart;
   wire valid = rf_valid & !ex_restart;
   always @(posedge clock) ex_valid   <= valid;

   reg  [`VMSB:0] ex_rs1_val;
   reg  [`VMSB:0] ex_rs2_val;

   /* Processor state, mostly CSRs */
   reg  [    1:0] priv;
   reg  [    4:0] csr_fflags;
   reg  [    2:0] csr_frm;
   reg  [    3:0] csr_mcause;
   reg  [`VMSB:0] csr_mcycle;
   reg  [`VMSB:0] csr_mepc;
   reg  [    7:0] csr_mie;
   reg  [`VMSB:0] csr_minstret;
   reg  [    7:0] csr_mip;
   reg  [`VMSB:0] csr_mscratch;
   reg  [`VMSB:0] csr_mstatus;
   reg  [`VMSB:0] csr_mtval;
   reg  [`VMSB:0] csr_mtvec;



   /* Updates to machine state */
   reg  [    3:0] ex_csr_mcause;
   reg  [`VMSB:0] ex_csr_mepc;
   reg  [`VMSB:0] ex_csr_mstatus;
   reg  [`VMSB:0] ex_csr_mtval;

   wire        ex_sign                  = ex_insn[31];
   wire [19:0] ex_sign20                = {20{ex_sign}};
   wire [11:0] ex_sign12                = {12{ex_sign}};

   // I-type
   wire [`VMSB:0] ex_i_imm              = {ex_sign20, ex_insn`funct7, ex_insn`rs2};

   // S-type
   wire [`VMSB:0] ex_s_imm              = {ex_sign20, ex_insn`funct7, ex_insn`rd};
   wire [`VMSB:0] ex_sb_imm             = {ex_sign20, ex_insn[7], ex_insn[30:25], ex_insn[11:8], 1'd0};

   // U-type
   wire [`VMSB:0] ex_uj_imm             = {ex_sign12, ex_insn[19:12], ex_insn[20], ex_insn[30:21], 1'd0};

   /* XXX style violation: operates directly on inputs; should be moved to decode */
   reg use_rs1, use_rs2;
   always @(*)
     if (!rf_valid)
       {use_rs2,use_rs1} = 0;
     else begin
        {use_rs2,use_rs1} = 0;
        case (insn`opcode)
          `BRANCH: {use_rs2,use_rs1} = 3;
          `OP:     {use_rs2,use_rs1} = 3;
          `STORE:  {use_rs2,use_rs1} = 3;

          `OP_IMM: {use_rs2,use_rs1} = 1;
          `LOAD:   {use_rs2,use_rs1} = 1;
          `JALR:   {use_rs2,use_rs1} = 1;
          `SYSTEM:
            case (insn`funct3)
              `CSRRS:  {use_rs2,use_rs1} = 1;
              `CSRRC:  {use_rs2,use_rs1} = 1;
              `CSRRW:  {use_rs2,use_rs1} = 1;
            endcase
        endcase
        if (insn`rs1 == 0) use_rs1 = 0;
        if (insn`rs2 == 0) use_rs2 = 0;
     end

   wire debug_bypass = 0 && valid;

   always @(posedge clock)
     if      (!use_rs1)
       ex_rs1_val <= 0;
     else if (insn`rs1 == ex_wb_rd && ex_valid && ex_insn`opcode != `LOAD) begin
       ex_rs1_val <= ex_wb_val;
       if (debug_bypass)
       $display("         %x: bypass r%1d from EX %x", pc, insn`rs1, ex_wb_val);
     end
     else if (insn`rs1 == me_wb_rd && me_valid) begin
       ex_rs1_val <= me_wb_val;
       if (debug_bypass)
       $display("         %x: bypass r%1d from ME %x", pc, insn`rs1, me_wb_val);
     end
     else begin
       ex_rs1_val <= rs1_val;
       if (debug_bypass)
       $display("         %x: get    r%1d from RF %x (ME r%d, me_valid %d)",
                pc, insn`rs1, rs1_val, me_wb_rd, me_valid);
     end

   always @(posedge clock)
     if      (!use_rs2)
       ex_rs2_val <= 0;
     else if (insn`rs2 == ex_wb_rd && ex_valid && ex_insn`opcode != `LOAD) begin
       ex_rs2_val <= ex_wb_val;
       if (debug_bypass)
       $display("         %x: bypass r%1d from EX %x", pc, insn`rs2, ex_wb_val);
     end
     else if (insn`rs2 == me_wb_rd && me_valid) begin
       ex_rs2_val <= me_wb_val;
       if (debug_bypass)
       $display("         %x: bypass r%1d from ME %x", pc, insn`rs2, me_wb_val);
     end
     else begin
       ex_rs2_val <= rs2_val;
       if (debug_bypass)
       $display("         %x: get    r%1d from RF %x", pc, insn`rs2, rs2_val);
     end

   wire [`VMSB:0] ex_rs1                = ex_rs1_val;
   wire [`VMSB:0] ex_rs2                = ex_rs2_val;

   wire [`VMSB:0] ex_rs1_val_cmp        = {ex_insn`br_unsigned,`VMSB'd0} ^ ex_rs1;
   wire [`VMSB:0] ex_rs2_val_cmp        = {ex_insn`br_unsigned,`VMSB'd0} ^ ex_rs2;
   wire           ex_cmp_eq             = ex_rs1 == ex_rs2;
   wire           ex_cmp_lt             = $signed(ex_rs1_val_cmp) < $signed(ex_rs2_val_cmp);
   wire           ex_branch_taken       = (ex_insn`br_rela ? ex_cmp_lt : ex_cmp_eq) ^ ex_insn`br_negate;

   wire [`VMSB:0] ex_rs2_val_imm        = ex_insn`opcode == `OP_IMM || ex_insn`opcode == `OP_IMM_32 ? ex_i_imm : ex_rs2;

   // XXX for timing, we should calculate csr_val already in RF and deal with the hazards
   reg [`VMSB:0]  csr_d;
   reg [`VMSB:0]  csr_val;
   always @(*)
     case (ex_insn`imm11_0)
       // Standard User R/W
       `CSR_FFLAGS:       csr_val = {27'd0, csr_fflags};
       `CSR_FRM:          csr_val = {29'd0, csr_frm};
       `CSR_FCSR:         csr_val = {24'd0, csr_frm, csr_fflags};

       `CSR_MSTATUS:      csr_val = csr_mstatus;
       `CSR_MISA:         csr_val = (2 << 30) | (1 << ("I"-"A"));
       `CSR_MIE:          csr_val = {24'd0, csr_mie};
       `CSR_MTVEC:        csr_val = csr_mtvec;

       `CSR_MSCRATCH:     csr_val = csr_mscratch;
       `CSR_MEPC:         csr_val = csr_mepc;
       `CSR_MCAUSE:       csr_val = {28'd0, csr_mcause};
       `CSR_MTVAL:        csr_val = csr_mtval;
       `CSR_MIP:          csr_val = {24'd0, csr_mip};

       `CSR_MCYCLE:       csr_val = csr_mcycle;
       `CSR_MINSTRET:     csr_val = csr_minstret;

       `CSR_PMPCFG0:      csr_val = 0;
       `CSR_PMPADDR0:     csr_val = 0;

       // Standard Machine RO
       `CSR_MVENDORID:    csr_val = 9;                          // F11
       `CSR_MARCHID:      csr_val = 0;                          // F12
       `CSR_MIMPID:       csr_val = 0;                          // F13
       `CSR_MHARTID:      csr_val = 0;                          // F14

       default:           begin
                          csr_val = 0;
                          if (ex_valid && ex_insn`opcode == `SYSTEM && ex_insn`funct3 != 0)
                            $display("                                                 Warning: CSR %x default to zero",
                                     ex_insn`imm11_0);
                          end
     endcase

   /* This is the main ALU, as combinational logic.  This will
      eventually be rewritten/refactored into a much denser circuit
      with enables derived in the previous stage.  For now this is
      easier to work with. */

   reg        ex_csr_we;
   reg        ex_trap;
   always @(*) begin
      ex_csr_we                         = 0;
      ex_restart                        = 0;
      ex_restart_pc                     = 0;

      ex_readenable                     = 0;
      ex_writeenable                    = 0;
      ex_writedata                      = ex_rs2_val;
      ex_funct3                         = ex_insn`funct3;
      ex_wb_rd                          = 0;
      ex_wb_val                         = 'hX;

      ex_priv                           = priv;
      ex_csr_mcause                     = csr_mcause;
      ex_csr_mepc                       = csr_mepc;
      ex_csr_mstatus                    = csr_mstatus;
      ex_csr_mtval                      = csr_mtval;

      ex_trap                           = 0;

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
                ex_trap                 = 1;
                ex_csr_mcause           = `CAUSE_ILLEGAL_INSTRUCTION;
                ex_csr_mtval            = 0;

                if (ex_valid)
                  $display("Illegal instruction %x:%x", ex_pc, ex_insn);
             end
           endcase
        end

        `BRANCH: begin
           ex_restart_pc                = ex_pc + ex_sb_imm;
           if (ex_branch_taken) begin
              ex_restart                = 1;
              if (ex_restart_pc[1:0]) begin
                 ex_trap                = 1;
                 ex_csr_mcause          = `CAUSE_MISALIGNED_FETCH;
                 ex_csr_mtval           = ex_restart_pc;
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
           ex_restart                   = 1;
           ex_restart_pc                = (ex_rs1_val + ex_i_imm) & ~32'd1;
           if (ex_restart_pc[1:0]) begin
              ex_wb_rd                  = 0;
              ex_trap                   = 1;
              ex_csr_mcause             = `CAUSE_MISALIGNED_FETCH;
              ex_csr_mtval              = ex_restart_pc;
           end
        end

        `JAL: begin
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = ex_pc + 4;
           ex_restart                   = 1;
           ex_restart_pc                = ex_pc + ex_uj_imm;
           if (ex_restart_pc[1:0]) begin
              ex_wb_rd                  = 0;
              ex_trap                   = 1;
              ex_csr_mcause             = `CAUSE_MISALIGNED_FETCH;
              ex_csr_mtval              = ex_restart_pc;
           end
        end

        `SYSTEM: begin
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = csr_val;
           ex_csr_we                    = 1;
           case (ex_funct3)
             `CSRRS:  begin csr_d       = csr_val |  ex_rs1; if (ex_insn`rs1 == 0) ex_csr_we = 0; end
             `CSRRC:  begin csr_d       = csr_val &~ ex_rs1; if (ex_insn`rs1 == 0) ex_csr_we = 0; end
             `CSRRW:  begin csr_d       =            ex_rs1; end
             `CSRRSI: begin csr_d       = csr_val |  {27'd0, ex_insn`rs1}; end
             `CSRRCI: begin csr_d       = csr_val &~ {27'd0, ex_insn`rs1}; end
             `CSRRWI: begin csr_d       =            {27'd0, ex_insn`rs1}; end
             `PRIV: begin
                ex_csr_we               = 0;
                ex_restart              = 1;
                case (ex_insn`imm11_0)
                  `ECALL, `EBREAK: begin
                     ex_trap            = 1;
                     ex_csr_mcause      = ex_insn`imm11_0 == `ECALL
                                          ? `CAUSE_USER_ECALL | priv
                                          : `CAUSE_BREAKPOINT;
                     ex_csr_mtval       = 0;
                  end

                  `MRET: begin
                     ex_restart_pc      = csr_mepc;
                     ex_csr_mstatus`MIE = csr_mstatus`MPIE;
                     ex_csr_mstatus`MPIE= 1;
                     ex_priv            = csr_mstatus`MPP;
                     ex_csr_mstatus`MPP = `PRV_U;
                  end

                  default: begin
                     ex_trap            = 1;
                     ex_csr_mcause      = `CAUSE_ILLEGAL_INSTRUCTION;
                     ex_csr_mtval       = 0;
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
                  ex_trap               = 1;
                  ex_csr_mcause         = `CAUSE_ILLEGAL_INSTRUCTION;
                  ex_csr_mtval          = 0;
                  if (ex_valid)
                    $display("Illegal instruction %x:%x", ex_pc, ex_insn);
               end
           endcase
        end

        `MISC_MEM:
            case (ex_funct3)
              `FENCE:  ;
              `FENCE_I: begin
                 ex_restart             = 1;
                 ex_restart_pc          = ex_pc + 4;
              end

              default: begin
                 ex_trap                = 1;
                 ex_csr_mcause          = `CAUSE_ILLEGAL_INSTRUCTION;
                 ex_csr_mtval           = 0;
                 if (ex_valid)
                   $display("Illegal instruction %x:%x", ex_pc, ex_insn);
              end
          endcase

        `LOAD: begin
           ex_readenable                = 1;
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = ex_rs1 + ex_i_imm;
           case (ex_insn`funct3)
             3, 6, 7: begin
                ex_trap                 = 1;
                ex_csr_mcause           = `CAUSE_ILLEGAL_INSTRUCTION;
                ex_csr_mtval            = 0;

                if (ex_valid)
                  $display("Illegal instruction %x:%x", ex_pc, ex_insn);
             end
           endcase
        end

        `STORE: begin
           ex_writeenable               = 1;
           ex_wb_val                    = ex_rs1 + ex_s_imm;
           case (ex_insn`funct3)
             3, 4, 5, 6, 7: begin
                ex_trap                 = 1;
                ex_csr_mcause           = `CAUSE_ILLEGAL_INSTRUCTION;
                ex_csr_mtval            = 0;

                if (ex_valid)
                  $display("Illegal instruction %x:%x", ex_pc, ex_insn);
             end
           endcase
        end

        default: begin
           ex_trap                      = 1;
           ex_csr_mcause                = `CAUSE_ILLEGAL_INSTRUCTION;
           ex_csr_mtval                 = 0;
           if (ex_valid)
             $display("Illegal instruction %x:%x", ex_pc, ex_insn);
        end
      endcase

      if (ex_trap) begin
         ex_restart_pc                  = csr_mtvec;
         ex_csr_mepc                    = ex_pc;
         ex_csr_mstatus`MPIE            = csr_mstatus`MIE;
         ex_csr_mstatus`MIE             = 0;
         ex_csr_mstatus`MPP             = priv;
         ex_priv                        = `PRV_M;
      end

      /* The order here is important, lowest priority first.  */
      if (use_rs1 && insn`rs1 == ex_wb_rd && ex_valid && ex_insn`opcode == `LOAD) begin
         $display("%5d    %x: load hazard on r%1d", $time/10, pc, insn`rs1);
         ex_restart                     = 1;
         ex_restart_pc                  = pc;
      end

      if (use_rs2 && insn`rs2 == ex_wb_rd && ex_valid && ex_insn`opcode == `LOAD) begin
         $display("%5d    %x: load hazard on r%1d", $time/10, pc, insn`rs2);
         ex_restart                     = 1;
         ex_restart_pc                  = pc;
      end

      if (!ex_valid) begin
         ex_csr_we                      = 0;
         ex_wb_rd                       = 0;
         ex_restart                     = 0;
      end

      if (reset) begin
         ex_csr_we                      = 0;
         ex_restart                     = 1;
         ex_restart_pc                  = `INIT_PC;
      end
   end

   always @(posedge clock) if (reset) begin
      priv                              <= `PRV_M;
      csr_fflags                        <= 0;
      csr_frm                           <= 0;
      csr_mcause                        <= 4'd0;
      csr_mcycle                        <= 0;
      csr_mepc                          <= 0;
      csr_mie                           <= 0;
      csr_minstret                      <= 0;
      csr_mip                           <= 0;
      csr_mscratch                      <= 0;
      csr_mstatus                       <= {31'd 3, 1'd 0};
      csr_mtval                         <= 0;
      csr_mtvec                         <= 0;
   end else begin
      csr_mcycle                        <= csr_mcycle + 1;

      if (ex_valid) begin
         /* Note, there's no conflicts as, by construction, the CSR
          instructions can't fault and thus ex_XXX will hold the old
          value of the CSR */

         priv                           <= ex_priv;
         csr_mcause                     <= ex_csr_mcause;
         csr_mepc                       <= ex_csr_mepc;
         csr_mstatus                    <= ex_csr_mstatus;
         csr_mtval                      <= ex_csr_mtval;
      end

      if (ex_csr_we)
         case (ex_insn`imm11_0)
           `CSR_FCSR:      {csr_frm,csr_fflags} <= csr_d[7:0];
           `CSR_FFLAGS:    csr_fflags   <= csr_d[4:0];
           `CSR_FRM:       csr_frm      <= csr_d[2:0];
//         `CSR_MCAUSE:    csr_mcause   <= csr_d;
//         `CSR_MCYCLE:    csr_mcycle   <= csr_d;
           `CSR_MEPC:      csr_mepc     <= csr_d & ~3;
           `CSR_MIE:       csr_mie      <= csr_d[7:0];
//         `CSR_MINSTRET:  csr_instret  <= csr_d;
           `CSR_MIP:       csr_mip[3]   <= csr_d[3];
           `CSR_MSCRATCH:  csr_mscratch <= csr_d;
           `CSR_MSTATUS:   csr_mstatus  <= csr_d & ~(15 << 13); // No FP or XS;
           `CSR_MTVEC:     csr_mtvec    <= csr_d;
//         `CSR_MTVAL:     csr_mtvec    <= csr_d;

           `CSR_PMPCFG0: ;
           `CSR_PMPADDR0: ;

           4095: ;
           default:
             $display("                                                 Warning: writing an unimplemented CSR %x", ex_insn`imm11_0);
         endcase
   end
endmodule
