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
               , input  wire [ 4:0]      me_wb_rd
               , input  wire [31:0]      me_wb_val

               , output reg              ex_valid
               , output reg [`VMSB:0]    ex_pc
               , output reg [31:0]       ex_insn
               , output reg [ 1:0]       ex_priv

               , output reg              ex_restart
               , output reg [`VMSB:0]    ex_restart_pc

               , output reg  [ 4:0]      ex_wb_rd
               , output reg  [`VMSB:0]   ex_wb_val

               , output reg              ex_readenable
               , output reg              ex_writeenable
               , output reg  [ 2:0]      ex_funct3
               , output reg  [`XMSB:0]   ex_writedata
               );

   /* We register all inputs, so ex_??? are inputs to EX after flops
      (this isn't the most natual way to write it but matches how we
      typically draw the pipelines).  */
   reg rf_valid = 0;
   always @(posedge clock) ex_pc      <= pc;
   always @(posedge clock) ex_insn    <= insn;
   always @(posedge clock) rf_valid   <= !ex_restart;
   wire valid = rf_valid & !ex_restart;
   always @(posedge clock) ex_valid   <= valid;

   reg  [`VMSB:0] ex_rs1_val;
   reg  [`VMSB:0] ex_rs2_val;

   /* Processor state, mostly CSRs */
   reg  [ 1:0] priv                     = `PRV_M;       // Current priviledge level
   // CSRS

   // URW
   reg  [ 4:0] csr_fflags               = 0;            // 001
   reg  [ 2:0] csr_frm                  = 0;            // 002

   reg  [`VMSB:0] csr_stvec             = 'h 100;       // 105

`ifdef not_hard_wired_to_zero
   // MRO, Machine Information Registers
   reg  [`VMSB:0] csr_mvendorid         = 0;            // f11
   reg  [`VMSB:0] csr_marchid           = 0;            // f12
   reg  [`VMSB:0] csr_mimpid            = 0;            // f13
   reg  [`VMSB:0] csr_mhartid           = 0;            // f14
`endif
   reg  [`VMSB:0] csr_satp              = 0;            // 180

   // MRW, Machine Trap Setup
   reg  [`VMSB:0] csr_mstatus           = {2'd 3, 1'd 0};// 300
   reg  [`VMSB:0] csr_medeleg           = 0;            // 302
   reg  [`VMSB:0] csr_mideleg           = 0;            // 303
   reg  [    7:0] csr_mie               = 0;            // 304
   reg  [`VMSB:0] csr_mtvec             = 0;            // 305

   // MRW, Machine Time and Counters
   // MRW, Machine Trap Handling
   reg  [`VMSB:0] csr_mscratch          = 0;            // 340
   reg  [`VMSB:0] csr_mepc              = 0;            // 341
   reg  [`VMSB:0] csr_mcause            = 0;            // 342
   reg  [`VMSB:0] csr_mtval             = 0;            // 343
   reg  [    7:0] csr_mip               = 0;            // 344

   // URO
   reg  [`VMSB:0] csr_mcycle            = 0;            // b00
   reg  [`VMSB:0] csr_mtime             = 0;            // b01? not used?
   reg  [`VMSB:0] csr_minstret          = 0;            // b02

   /* Updates to machine state */
   reg  [`VMSB:0] ex_csr_mcause;
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

   reg  [`VMSB:0] wb_wb_val; always @(posedge clock) wb_wb_val <= ex_wb_val;
   reg  [    4:0] wb_wb_rd ; always @(posedge clock) wb_wb_rd  <= ex_wb_rd;

   reg use_rs1, use_rs2;
   always @(*)
     if (!valid)
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
     end

   wire debug_bypass = 0 && valid;

   always @(posedge clock)
     if      (!use_rs1 || insn`rs1 == 0)
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
     if      (!use_rs2 || insn`rs2 == 0)
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

   always @(posedge clock)
     if (use_rs1 && insn`rs1 != 0 && insn`rs1 == ex_wb_rd && ex_valid &&
         ex_insn`opcode == `LOAD)
       begin
          $display("         %x: load hazard on r%1d", pc, insn`rs1);
          $finish;
       end

   always @(posedge clock)
     if (use_rs2 && insn`rs2 != 0 && insn`rs2 == ex_wb_rd && ex_valid &&
         ex_insn`opcode == `LOAD)
       begin
          $display("         %x: load hazard on r%1d", pc, insn`rs2);
          $finish;
       end

   wire [`VMSB:0] ex_rs1                = ex_rs1_val;
   wire [`VMSB:0] ex_rs2                = ex_rs2_val;

   wire [`VMSB:0] ex_rs1_val_cmp        = (ex_insn`br_unsigned << `VMSB) ^ ex_rs1;
   wire [`VMSB:0] ex_rs2_val_cmp        = (ex_insn`br_unsigned << `VMSB) ^ ex_rs2;
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
       `CSR_FFLAGS:       csr_val = csr_fflags;                 // 001
       `CSR_FRM:          csr_val = csr_frm;                    // 002
       `CSR_FCSR:         csr_val = {csr_frm, csr_fflags};      // 003

       `CSR_MSTATUS:      csr_val = csr_mstatus;                // 300
       `CSR_MISA:         csr_val = (2 << 30) | (1 << ("I"-"A"));//301
       `CSR_MIE:          csr_val = csr_mie;                    // 304
       `CSR_MTVEC:        csr_val = csr_mtvec;                  // 305
       `CSR_MCOUNTEREN:   csr_val = 0;                          // 306

       `CSR_MSCRATCH:     csr_val = csr_mscratch;               // 340
       `CSR_MEPC:         csr_val = csr_mepc;                   // 341
       `CSR_MCAUSE:       csr_val = csr_mcause;                 // 342
       `CSR_MTVAL:        csr_val = csr_mtval;                  // 343
       `CSR_MIP:          csr_val = csr_mip;                    // 344

       `CSR_MCYCLE:       csr_val = csr_mcycle;
       `CSR_MINSTRET:     csr_val = csr_minstret;

       `CSR_PMPCFG0:      csr_val = 0;                          // 3A0
       `CSR_PMPADDR0:     csr_val = 0;                          // 3B0

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

   reg [11:0] ex_csr_waddr;
   always @(*) begin
      ex_csr_waddr                      = ~0;
      ex_restart                        = 0;
      ex_restart_pc                     = 'hX;

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

      case (ex_insn`opcode)
        `OP_IMM, `OP: begin
           ex_wb_rd                     = ex_insn`rd;
           case (ex_funct3)
             `ADDSUB: ex_wb_val         = ex_insn[30] && ex_insn`opcode == `OP
                                          ?       ex_rs1  -         ex_rs2_val_imm
                                          :       ex_rs1  +         ex_rs2_val_imm;
             `SLT:    ex_wb_val         = $signed(ex_rs1) < $signed(ex_rs2_val_imm); // or flip MSB of both operands
             `SLTU:   ex_wb_val         =         ex_rs1  <         ex_rs2_val_imm;
             `XOR:    ex_wb_val         =         ex_rs1  ^         ex_rs2_val_imm;
             `SR_:    if (ex_insn[30])
                        ex_wb_val       = $signed(ex_rs1) >>>       ex_rs2_val_imm[4:0];
                      else
                        ex_wb_val       =         ex_rs1  >>        ex_rs2_val_imm[4:0];
             `SLL:    ex_wb_val         =         ex_rs1  <<        ex_rs2_val_imm[4:0];
             `OR:     ex_wb_val         =         ex_rs1  |         ex_rs2_val_imm;
             `AND:    ex_wb_val         =         ex_rs1  &         ex_rs2_val_imm;
           endcase
        end

        `BRANCH: begin
           ex_restart_pc                = ex_pc + ex_sb_imm;
           if (ex_branch_taken)
             ex_restart                 = 1;
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
        end

        `JAL: begin
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = ex_pc + 4;
           ex_restart                   = 1;
           ex_restart_pc                = ex_pc + ex_uj_imm;
        end

        `SYSTEM: begin
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = csr_val;
           ex_csr_waddr                 = ex_insn`imm11_0;
           case (ex_funct3)
             `CSRRS:  begin csr_d       = csr_val |  ex_rs1; if (ex_insn`rs1 == 0) ex_csr_waddr = ~0; end
             `CSRRC:  begin csr_d       = csr_val &~ ex_rs1; if (ex_insn`rs1 == 0) ex_csr_waddr = ~0; end
             `CSRRW:  begin csr_d       =            ex_rs1; end
             `CSRRSI: begin csr_d       = csr_val |  ex_insn`rs1; end
             `CSRRCI: begin csr_d       = csr_val &~ ex_insn`rs1; end
             `CSRRWI: begin csr_d       =            ex_insn`rs1; end
             `PRIV: begin
                ex_csr_waddr            = ~0;
                ex_restart              = 1;
                case (ex_insn`imm11_0)
                  `ECALL: begin
                     ex_restart_pc      = csr_mtvec;
                     ex_csr_mcause      = `CAUSE_USER_ECALL | priv;
                     ex_csr_mepc        = ex_pc;
                     ex_csr_mtval       = 0;
                     ex_csr_mstatus`MPIE= csr_mstatus`MIE;
                     ex_csr_mstatus`MIE = 0;
                     ex_csr_mstatus`MPP = priv;
                     ex_priv            = `PRV_M;
                  end
                  `MRET: begin
                     ex_restart_pc      = csr_mepc;
                     ex_csr_mstatus`MIE = csr_mstatus`MPIE;
                     ex_csr_mstatus`MPIE= 1;
                     ex_priv            = csr_mstatus`MPP;
                     ex_csr_mstatus`MPP = `PRV_U;
                  end
                  //`EBREAK: $finish; // XXX
                  default: begin
                     $display("NOT IMPLEMENTED SYSTEM.PRIV 0x%x (inst %x)",
                              ex_insn`imm11_0, ex_insn);
                     $finish;
                  end
                endcase
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

              default: if (ex_valid) begin
                 $display("%05d  %x %x *** Unsupported", $time, ex_pc, ex_insn, ex_insn`opcode);
                 $finish;
              end
          endcase

        `LOAD: begin
           ex_readenable                = 1;
           ex_wb_rd                     = ex_insn`rd;
           ex_wb_val                    = ex_rs1 + ex_i_imm;
        end
        `STORE: begin
           ex_writeenable               = 1;
           ex_wb_val                    = ex_rs1 + ex_s_imm;
        end

        default:
          if (ex_valid) begin
             $display("%05d  %x %x *** Unsupported opcode %d", $time, ex_pc, ex_insn, ex_insn`opcode);
             $finish;
          end
      endcase

      if (!ex_valid) begin
         ex_csr_waddr                   = ~0;
         ex_restart                     = 0;
      end

      if (reset) begin
         ex_restart                     = 1;
         ex_restart_pc                  = `INIT_PC;
      end
   end

   always @(posedge clock) begin
      /* Note, there's no conflicts as, by construction, the CSR
         instructions can't fault and thus ex_XXX will hold the old
         value of the CSR */

      priv                              <= ex_priv;
      csr_mcause                        <= ex_csr_mcause;
      csr_mepc                          <= ex_csr_mepc;
      csr_mstatus                       <= ex_csr_mstatus;
      csr_mtval                         <= ex_csr_mtval;

      case (ex_csr_waddr)
        `CSR_FFLAGS:    csr_fflags           <= csr_d;
        `CSR_FRM:       csr_frm              <= csr_d;
        `CSR_FCSR:      {csr_frm,csr_fflags} <= csr_d;

        `CSR_MSTATUS:   csr_mstatus          <= csr_d & ~(15 << 12); // No FP or XS;
        `CSR_MEDELEG:   csr_medeleg          <= csr_d;
        `CSR_MIDELEG:   csr_mideleg          <= csr_d;
        `CSR_MIE:       csr_mie              <= csr_d;

        `CSR_MSCRATCH:  csr_mscratch         <= csr_d;
        `CSR_MEPC:      csr_mepc             <= csr_d;
        `CSR_MIP:       csr_mip[3]           <= csr_d[3];
        `CSR_MTVEC:     csr_mtvec            <= csr_d;
        `CSR_STVEC:     csr_stvec            <= csr_d;
        `CSR_SATP:      csr_satp             <= csr_d;

        `CSR_PMPCFG0: ;
        `CSR_PMPADDR0: ;

        4095: ;
        default:
          $display("                                                 Warning: writing an unimplemented CSR %x", ex_csr_waddr);
      endcase
   end
endmodule