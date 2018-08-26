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

               , output reg              ex_valid = 0
               , output reg [`VMSB:0]    ex_pc
               , output reg [31:0]       ex_insn

               , output reg              ex_restart
               , output reg [`VMSB:0]    ex_restart_pc

               , output reg              ex_wben
               , output reg  [63:0]      ex_wb_val
               , output reg  [ 4:0]      ex_wb_rd

               // Mem interface
               , output reg              ex_mem_valid = 0
               , output reg              ex_mem_writeenable
               , output reg  [`VMSB:0]   ex_mem_address
               , output reg  [`XMSB:0]   ex_mem_writedata
               , output reg  [1:0]       ex_mem_sizelg2
               , output reg  [4:0]       ex_mem_readtag // ignored when writedata
               , output reg              ex_mem_readsignextend

               , input  wire             me_ready

               , input  wire             me_readdatavalid // Have read result
               , input  wire [4:0]       me_readdatatag
               , input  wire [`XMSB:0]   me_readdata); // Signextended


   reg reset = 0;

   /* We register all inputs, so ex_XXX are inputs to EX after flops
      (this isn't the most natual way to write it but matches how we
      typically draw the pipelines).  */
   reg rf_valid = 0;
   always @(posedge clock) ex_pc      <= pc;
   always @(posedge clock) ex_insn    <= insn;
   always @(posedge clock) rf_valid   <= !ex_restart;
   always @(posedge clock) ex_valid   <= rf_valid & !ex_restart;

   reg  [63:0] ex_rs1_val       = 0; always @(posedge clock) ex_rs1_val <= rs1_val;
   reg  [63:0] ex_rs2_val       = 0; always @(posedge clock) ex_rs2_val <= rs2_val;

   /* Processor state, mostly CSRs */

   reg  [ 1:0] ex_prv           = `PRV_M;       // Current priviledge level
   reg  [ 1:0] ex_next_prv;                     // Next priviledge level
   always @(posedge clock) ex_prv <= ex_next_prv;

   // CSRS

   // URW
   reg  [ 4:0] csr_fflags       = 0;            // 001
   reg  [ 2:0] csr_frm          = 0;            // 002

   reg  [63:0] csr_stvec        = 'h 100;       // 105

`ifdef not_hard_wired_to_zero
   // MRO, Machine Information Registers
   reg  [63:0] csr_mvendorid    = 0;            // f11
   reg  [63:0] csr_marchid      = 0;            // f12
   reg  [63:0] csr_mimpid       = 0;            // f13
   reg  [63:0] csr_mhartid      = 0;            // f14
`endif
   reg  [63:0] csr_satp         = 0;            // 180

   // MRW, Machine Trap Setup
   reg  [63:0] csr_mstatus      = {2'd 3, 1'd 0};// 300
   reg  [63:0] csr_medeleg      = 0;            // 302
   reg  [63:0] csr_mideleg      = 0;            // 303
   reg  [ 7:0] csr_mie          = 0;            // 304
   reg  [63:0] csr_mtvec        = 'h 100;       // 305

   // MRW, Machine Time and Counters
   // MRW, Machine Trap Handling
   reg  [63:0] csr_mscratch     = 0;            // 340
   reg  [63:0] csr_mepc         = 0;            // 341
   reg  [63:0] csr_mcause       = 0;            // 342
   reg  [63:0] csr_mtval        = 0;            // 343
   reg  [ 7:0] csr_mip          = 0;            // 344

   // URO
   reg  [63:0] csr_mcycle       = 0;            // b00
   reg  [63:0] csr_mtime        = 0;            // b01? not used?
   reg  [63:0] csr_minstret     = 0;            // b02


   wire        ex_sign          = ex_insn[31];
   wire [51:0] ex_sign52        = {52{ex_sign}};
   wire [43:0] ex_sign44        = {44{ex_sign}};

   // I-type
   wire [63:0] ex_i_imm         = {ex_sign52, ex_insn`funct7, ex_insn`rs2};

   // S-type
   wire [63:0] ex_s_imm         = {ex_sign52, ex_insn`funct7, ex_insn`rd};
   wire [63:0] ex_sb_imm        = {ex_sign52, ex_insn[7], ex_insn[30:25], ex_insn[11:8], 1'd0};

   // U-type
   wire [63:0] ex_uj_imm        = {ex_sign44, ex_insn[19:12], ex_insn[20], ex_insn[30:21], 1'd0};

   reg  [63:0] wb_wb_val        = 0; always @(posedge clock) wb_wb_val <= ex_wb_val;
   reg  [ 4:0] wb_wb_rd         = 0; always @(posedge clock) wb_wb_rd  <= ex_wb_rd;
   reg  [ 4:0] wb_wben          = 0; always @(posedge clock) wb_wben   <= ex_wben;

   /* The bypassed register values have a high fanout so it's
      important to drive them directly from a flop.  We unfortunately
      don't do that here - yet. (It's a little tricky to get correct
      in the presence of pipeline bubles).

   wire        rs1_forward_ex   = ex_insn`rs1 == wb_wb_rd && ex_wben;
   wire        rs2_forward_ex   = ex_insn`rs2 == wb_wb_rd && ex_wben;
  */

   wire [63:0] ex_rs1           = /* rs1_forward_ex ? wb_wb_val : */ ex_rs1_val;
   wire [63:0] ex_rs2           = /* rs2_forward_ex ? wb_wb_val : */ ex_rs2_val;

   wire [63:0] ex_rs1_val_cmp   = (~ex_insn`br_unsigned << 63) ^ ex_rs1;
   wire [63:0] ex_rs2_val_cmp   = (~ex_insn`br_unsigned << 63) ^ ex_rs2;
   wire        ex_cmp_eq        = ex_rs1 == ex_rs2;
   wire        ex_cmp_lt        = ex_rs1_val_cmp  < ex_rs2_val_cmp;
   wire        ex_branch_taken  = (ex_insn`br_rela ? ex_cmp_lt : ex_cmp_eq) ^ ex_insn`br_negate;

   wire [63:0] ex_rs2_val_imm   = ex_insn`opcode == `OP_IMM ? ex_i_imm : ex_rs2;

   // XXX for timing, we should calculate csr_val already in RF and deal with the hazards
   reg [11:0]  csr_addr;
   reg [63:0]  csr_d;
   reg [63:0]  csr_val;
   always @(*)
     case (ex_insn`imm11_0)
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
                          if (ex_valid && ex_insn`opcode == `SYSTEM)
                            $display("                                                 Warning: CSR %x default to zero", ex_insn`imm11_0);
                          end
     endcase

/*
   always @(posedge clock) if (valid && rs1_forward_ex)
     $display("%05d  %8x *** Forwarding rs1 (%x) from EX", $time, ex_pc, ex_wb_val);
   always @(posedge clock) if (valid && ex_rs2_forward_ex)
     $display("%05d  %8x *** Forwarding ex_rs2 (%x) from EX", $time, ex_pc, ex_wb_val);
*/

   always @(*) begin
      csr_addr = ~0;
      ex_restart = 0;
      ex_wben = 0;
      ex_mem_valid = 0;
      ex_next_prv = ex_prv;

      case (ex_insn`opcode)
        `OP_IMM, `OP: begin
           ex_wben   = |ex_insn`rd;
           ex_wb_rd  = ex_insn`rd;
           case (ex_insn`funct3)
             `ADDSUB: if (ex_insn[30] && ex_insn`opcode == `OP)
               ex_wb_val = ex_rs1 - ex_rs2_val_imm;
             else
               ex_wb_val = ex_rs1 + ex_rs2_val_imm;
             `SLL:  ex_wb_val = ex_rs1 << ex_rs2_val_imm[4:0];
             `SLT:  ex_wb_val = $signed(ex_rs1) < $signed(ex_rs2_val_imm); // flip MSB of both operands
             `SLTU: ex_wb_val = ex_rs1 < ex_rs2_val_imm;
             `XOR:  ex_wb_val = ex_rs1 ^ ex_rs2_val_imm;
             `SR_:  if (ex_insn[30])
               ex_wb_val = $signed(ex_rs1) >>> ex_rs2_val_imm[4:0];
             else
               ex_wb_val = ex_rs1 >> ex_rs2_val_imm[4:0];
             `OR:   ex_wb_val = ex_rs1 | ex_rs2_val_imm;
             `AND:  ex_wb_val = ex_rs1 & ex_rs2_val_imm;
             default: ex_wben = 0;
           endcase
        end

        `BRANCH: begin
           ex_restart_pc = ex_pc + ex_sb_imm;
           if (ex_branch_taken)
             ex_restart = 1;
        end

        `AUIPC: begin
           ex_wben   = |ex_insn`rd;
           ex_wb_rd  = ex_insn`rd;
           ex_wb_val = ex_pc + {{32{ex_insn[31]}},ex_insn[31:12], 12'd0}; // XXX ex_sign extended?
        end

        `JAL: begin
           ex_wben       = |ex_insn`rd;
           ex_wb_rd      = ex_insn`rd;
           ex_wb_val     = ex_pc + 4;
           ex_restart    = 1;
           ex_restart_pc = ex_pc + ex_uj_imm;
        end

        `SYSTEM: begin
           ex_wben   = |ex_insn`rd;
           ex_wb_rd  = ex_insn`rd;
           ex_wb_val = csr_val;
           csr_addr = ex_insn`imm11_0;
           case (ex_insn`funct3)
             `CSRRS:  begin csr_d = csr_val |  ex_rs1; if (ex_insn`rs1 == 0) csr_addr = ~0; end
             `CSRRC:  begin csr_d = csr_val &~ ex_rs1; if (ex_insn`rs1 == 0) csr_addr = ~0; end
             `CSRRW:  begin csr_d =            ex_rs1; end
             `CSRRSI: begin csr_d = csr_val |  ex_insn`rs1; end
             `CSRRCI: begin csr_d = csr_val &~ ex_insn`rs1; end
             `CSRRWI: begin csr_d =            ex_insn`rs1; end
             `PRIV: begin
                ex_wben = 0;
                csr_addr = ~0;
                ex_restart = 1;
                case (ex_insn`imm11_0)
                  `ECALL: begin
                     ex_restart_pc = csr_mtvec;
                     // XXX Handle delegation if ex_prv = PRV_S
                     csr_mcause = `CAUSE_USER_ECALL | ex_prv;
                     csr_mepc = ex_pc;
                     csr_mtval = 0;
                     csr_mstatus`MPIE = csr_mstatus`MIE;
                     csr_mstatus`MIE = 0;
                     csr_mstatus`MPP = ex_prv;
                     ex_next_prv = `PRV_S;
                  end
                  `MRET: begin
                     ex_restart_pc = csr_mepc;
                     csr_mstatus`MIE = csr_mstatus`MPIE;
                     csr_mstatus`MPIE = 1;
                     ex_next_prv = csr_mstatus`MPP;
                     csr_mstatus`MPP = `PRV_U;
                  end
                  //`EBREAK: $finish; // XXX
                  default: begin
                     $display("NOT IMPLEMENTED SYSTEM.PRIV 0x%x (inst %x)",
                              ex_insn`imm11_0, ex_insn);
                     $finish;
                  end
                endcase
             end
             default: begin
                ex_wben = 0;
                csr_addr = ~0;
             end
          endcase
        end
        `MISC_MEM:
            case (ex_insn`funct3)
              `FENCE:  ;
              `FENCE_I: begin
                 ex_restart    = 1;
                 ex_restart_pc = ex_pc + 4;
              end

              default: if (ex_valid) begin
                 $display("%05d  %x %x *** Unsupported", $time, ex_pc, ex_insn, ex_insn`opcode);
                 $finish;
              end
          endcase

        `STORE: begin
           ex_mem_valid       = 1;
           ex_mem_writeenable = 1;
           ex_mem_address     = ex_rs1 + ex_s_imm;
           ex_mem_writedata   = ex_rs2_val;
           ex_mem_sizelg2     = ex_insn`funct3;
        end

        default:
          if (ex_valid) begin
             $display("%05d  %x %x *** Unsupported opcode %d", $time, ex_pc, ex_insn, ex_insn`opcode);
             $finish;
          end
      endcase

      if (!ex_valid) begin
         ex_wben = 0;
         csr_addr = ~0;
         ex_mem_valid = 0;
         ex_restart = 0;
      end

      if (reset) begin
         ex_restart = 1;
         ex_restart_pc = `INIT_PC;
         reset = 0;
      end
   end

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

/*
   always @(posedge clock)
     if (ex_valid) begin
        $display("%05d  prv = %d", $time, ex_prv);
        case (ex_insn`opcode)
          `BRANCH:
            $display("%05d  Bcc 0x%1x, 0x%1x -> %d (eq %d, lt %d, N %d)", $time,
                     ex_rs1, ex_rs2, ex_branch_taken,
                     ex_cmp_eq,
                     ex_cmp_lt,
                     ex_insn`br_negate);
        endcase
     end
*/
endmodule
