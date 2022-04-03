// -----------------------------------------------------------------------
//
//   Copyright 2016,2018,2020,2022 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is the backend of the YARVI2 pipeline which takes in instructions
from the frontend (valid, pc, insn), decodes, fetches registers,
executes (including loads and stores), and write back results to the
register file.

We have five stages:

 s1   s2   s3      s4      s5
 IF | DE | EX/M1 | CM/M2 | M3/WB

IF: load instruction
DE: read registers and decode instruction and forward registers from EX, CM, WB
M1: calculate the load address
M2: access arrays
M3: way selection and data alignment/sign-extension
CM: restart, or flush
WB: write rf & /store to memory

Names prefixed with s2_, s1_, s3_, s4_, ... are the *outputs of the
corresponding stages*..

Currently the pipeline can be restarted (and flushed) only from CM and
causes the clear of all valid bits.

The pipeline might be invalidated or restarted for several reasons:
 - fetch mispredicted a branch and fed us the wrong instructions.
 - we need a value that is still being loaded from memory
 - instruction traps, like misaligned loads/stores
 - interrupts (which are taken in CM)

TODO:
 - add more accounting to enable "IPC stacks", that is, counting of
   cycles wasted due to all the reasons above.

*************************************************************************/

/* The width comparisons in Verilator are completely broken. */
/* verilator lint_off WIDTH */

`include "yarvi.h"
`default_nettype none

module yarvi
  ( input  wire             clock
  , input  wire             reset

  , output reg              retire_valid = 0
  , output reg [ 1:0]       retire_priv
  , output reg [`VMSB:0]    retire_pc
  , output reg [31:0]       retire_insn
  , output reg [ 4:0]       retire_rd
  , output reg [`XMSB:0]    retire_wb_val
  , output reg [   31:0]    debug);




   /* Processor architectual state (excluding pc) */
   /* Data & code memory, 2R1W */
   reg  [   31:0] data[(1 << (`PMSB-1)) - 1:0];
   reg  [   31:0] code[(1 << (`PMSB-1)) - 1:0];
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
   reg  [   63:0] mtime;
   reg  [   63:0] mtimecmp;




   // Pipeline rules:
   //
   // P0: One stage is denoted the "committing" stage and all stages
   //     prior are considered "speculative" and will be flush when
   //     restart is asserted (that is, made invalid).
   //
   // P1: The committing stage _may_ flush its own instruction too
   //     (eg., in the case of an illegal instruction).
   //
   // P2: Architectural state can only be update by the committing
   //     stage or a later stage, and only if the stage is valid.
   //     (cycle counter is an exception to this).
   //
   // P3: No stage past the committing stage can be flushed
   //
   // P4: The committing stage can only restart and flush the pipeline
   //     if the stage is valid (XXX This might not be necessary nor
   //     desirable, but currently it would be a bug otherwise)
   //
   wire             restart;
   wire [`VMSB:0]   restart_pc;
   wire             stall;




   reg  [`VMSB:0]   s0_pc;
   reg  [31:0]      s0_insn;
   always @(posedge clock) begin
      last_s0_valid <= !restart;
      s0_pc         <= restart ? restart_pc :
                       stall ? s0_pc :
                       s0_pc + 4;
      s0_insn       <= code[restart ? restart_pc[`PMSB:2] :
                            stall ? s0_pc[`PMSB:2] :
                            s0_pc[`PMSB:2] + 1];
   end




   reg              last_s0_valid = 0;
   wire             s05_valid = last_s0_valid & !restart;
   reg  [`VMSB:0]   s05_pc;
   reg  [31:0]      s05_insn;
   always @(posedge clock) if (!stall | restart) begin
      last_s05_valid <= s05_valid;
      s05_pc         <= s0_pc;
      s05_insn       <= s0_insn;
   end




   reg  [`XMSB:0]   s1_pc;
   reg  [   31:0]   s1_insn;
   always @(posedge clock)
     last_s1_valid <= s1_valid;
   always @(posedge clock) if (!stall | restart) begin
      s1_pc         <= s05_pc;
      s1_insn       <= s05_insn;
   end

   wire [`XMSB-12:0] s1_sext12    = {(`XMSB-11){s1_insn[31]}};
   wire [`XMSB   :0] s1_i_imm     = {s1_sext12, s1_insn`funct7, s1_insn`rs2};
   wire [`XMSB   :0] s1_s_imm     = {s1_sext12, s1_insn`funct7, s1_insn`rd};

   reg              last_s05_valid = 0;
   wire             s1_valid = last_s05_valid & !restart;
   wire             s1_use_rs1, s1_use_rs2;
   wire [    4:0]   s1_rd;

   /* NB: r0 is not considered used */
   yarvi_dec_reg_usage yarvi_dec_reg_usage_inst0(s1_valid, s1_insn,
                                                 s1_use_rs1, s1_use_rs2, s1_rd);

   wire [    4:0]   s1_opcode = s1_insn`opcode;
   reg              s1_op2_imm_use;
   reg  [`XMSB:0]   s1_op2_imm;
   always @(*)
     {s1_op2_imm_use, s1_op2_imm}
                 = s1_insn`opcode == `AUIPC ||
                   s1_insn`opcode == `LUI    ? {1'd1, s1_insn[31:12], 12'd 0} :
                   s1_insn`opcode == `JALR  ||
                   s1_insn`opcode == `JAL    ? {1'd1, 32'd 4}              :
                   s1_insn`opcode == `SYSTEM ? {1'd1, 32'd 0}              :
                   s1_insn`opcode == `OP_IMM ||
                   s1_insn`opcode == `OP_IMM_32 ||
                   s1_insn`opcode == `LOAD   ? {1'd1, s1_i_imm}            :
                   s1_insn`opcode == `STORE  ? {1'd1, s1_s_imm}            :
                                       0;


assign stall =
 s1_use_rs1 && s1_insn`rs1 == s2_rd && s2_insn`opcode == `LOAD ||
 s1_use_rs2 && s1_insn`rs2 == s2_rd && s2_insn`opcode == `LOAD ||
 s1_use_rs1 && s1_insn`rs1 == s3_rd && s3_insn`opcode == `LOAD ||
 s1_use_rs2 && s1_insn`rs2 == s3_rd && s3_insn`opcode == `LOAD;

   reg              stall_p = 0;
   always @(posedge clock) stall_p <= stall;

   reg              last_s1_valid = 0;
   wire             s2_valid = last_s1_valid & !restart & !stall_p;
   reg  [`XMSB:0]   s2_pc;
   reg  [   31:0]   s2_insn;
   reg  [    4:0]   s2_rd;
   reg  [`XMSB  :0] s2_rs1_rf;
   reg  [`XMSB  :0] s2_rs2_rf;
   reg  [`XMSB:0]   s2_op2_imm;

   always @(posedge clock)
     last_s2_valid  <= s2_valid;

   always @(posedge clock) begin
      s2_pc          <= s1_pc;
      s2_insn        <= s1_insn;
      s2_rd          <= stall ? 0 : s1_rd;
      s2_rs1_rf      <= regs[s1_insn`rs1];
      s2_rs2_rf      <= regs[s1_insn`rs2];
      s2_op2_imm     <= s1_op2_imm;
   end

   wire [`XMSB-12:0] s2_sext12 = {(`XMSB-11){s2_insn[31]}};
   wire [`XMSB-20:0] s2_sext20 = {(`XMSB-19){s2_insn[31]}};
   wire [`XMSB   :0] s2_i_imm  = {s2_sext12, s2_insn`funct7, s2_insn`rs2};
   wire [`XMSB   :0] s2_sb_imm = {s2_sext12, s2_insn[7], s2_insn[30:25], s2_insn[11:8], 1'd0};
   wire [`XMSB   :0] s2_s_imm  = {s2_sext12, s2_insn`funct7, s2_insn`rd};
   wire [`XMSB   :0] s2_uj_imm = {s2_sext20, s2_insn[19:12], s2_insn[20], s2_insn[30:21], 1'd0};
   wire [       4:0] s2_opcode = s2_insn`opcode;
   reg  [`XMSB   :0] s2_csr_val;
   always @(posedge clock)
     case (s1_insn`imm11_0)
       // Standard User R/W
       `CSR_FFLAGS:       s2_csr_val <= {27'd0, csr_fflags};
       `CSR_FRM:          s2_csr_val <= {29'd0, csr_frm};
       `CSR_FCSR:         s2_csr_val <= {24'd0, csr_frm, csr_fflags};

       `CSR_MSTATUS:      s2_csr_val <= csr_mstatus;
       `CSR_MISA:         s2_csr_val <= (32'd 2 << 30) | (32'd 1 << ("I"-"A"));
       `CSR_MIE:          s2_csr_val <= csr_mie;
       `CSR_MTVEC:        s2_csr_val <= csr_mtvec;

       `CSR_MSCRATCH:     s2_csr_val <= csr_mscratch;
       `CSR_MEPC:         s2_csr_val <= csr_mepc;
       `CSR_MCAUSE:       s2_csr_val <= csr_mcause;
       `CSR_MTVAL:        s2_csr_val <= csr_mtval;
       `CSR_MIP:          s2_csr_val <= csr_mip;
       `CSR_MIDELEG:      s2_csr_val <= csr_mideleg;
       `CSR_MEDELEG:      s2_csr_val <= csr_medeleg;

       `CSR_MCYCLE:       s2_csr_val <= csr_mcycle;
       `CSR_MINSTRET:     s2_csr_val <= csr_minstret;

       `CSR_PMPCFG0:      s2_csr_val <= 0;
       `CSR_PMPADDR0:     s2_csr_val <= 0;

       // Standard Machine RO
       `CSR_MVENDORID:    s2_csr_val <= `VENDORID_YARVI;
       `CSR_MARCHID:      s2_csr_val <= 0;
       `CSR_MIMPID:       s2_csr_val <= 0;
       `CSR_MHARTID:      s2_csr_val <= 0;

       `CSR_SEPC:         s2_csr_val <= csr_sepc;
       `CSR_SCAUSE:       s2_csr_val <= csr_scause;
       `CSR_STVAL:        s2_csr_val <= csr_stval;
       `CSR_STVEC:        s2_csr_val <= csr_stvec;

       `CSR_CYCLE:        s2_csr_val <= csr_mcycle;
       `CSR_INSTRET:      s2_csr_val <= csr_minstret;

        default:          s2_csr_val <= 0;
     endcase



   /* ALU, produces s3_wb_val */


   reg              last_s2_valid = 0;
   wire             s3_valid = last_s2_valid & !restart;
   reg  [`XMSB:0]   s3_pc;
   reg  [   31:0]   s3_insn;
   reg  [    4:0]   s3_rd;
   wire [`XMSB:0]   s3_wb_val;
   wire [    4:0]   s3_opcode = s3_insn`opcode;
   reg  [`XMSB:0]   s3_sb_imm;
   reg  [`XMSB:0]   s3_s_imm;
   reg  [`XMSB:0]   s3_i_imm;
   reg  [`XMSB:0]   s3_uj_imm;
   reg  [`XMSB:0]   s3_rs1;
   reg  [`XMSB:0]   s3_rs2;
   reg  [`XMSB:0]   s3_csr_val;

   always @(posedge clock) begin
      last_s3_valid    <= s3_valid;
   end

   reg s3_alu_sub = 0;
   always @(posedge clock)
     s3_alu_sub <= (s2_opcode == `OP     && s2_insn`funct3 == `ADDSUB && s2_insn[30] ||
                    s2_opcode == `OP     && s2_insn`funct3 == `SLT                   ||
                    s2_opcode == `OP     && s2_insn`funct3 == `SLTU                  ||
                    s2_opcode == `OP_IMM && s2_insn`funct3 == `SLT                   ||
                    s2_opcode == `OP_IMM && s2_insn`funct3 == `SLTU                  ||
                    s2_opcode == `BRANCH);

   reg s3_alu_ashr = 0;
   always @(posedge clock)
     s3_alu_ashr <= s2_insn[30];

   reg [2:0] s3_alu_funct3 = 0;
   always @(posedge clock)
     s3_alu_funct3 <= (s2_opcode == `OP        ||
                       s2_opcode == `OP_IMM    ||
                       s2_opcode == `OP_IMM_32 ? s2_insn`funct3 : `ADDSUB);

   reg [`XMSB:0] s3_alu_op1, s3_alu_op2;

   reg [2:0]     s2_alu_op1_src;
   reg [2:0]     s2_alu_op2_src;

   always @(posedge clock)
     s2_alu_op1_src
       <= s1_opcode == `LUI   ||
          s1_opcode == `AUIPC ||
          s1_opcode == `JALR  ||
          s1_opcode == `JAL    ? 0 :
          s1_opcode == `SYSTEM ? 7 :
          !s1_use_rs1          ? 1 :
          s1_insn`rs1 == s2_rd ? 2 :
          s1_insn`rs1 == s3_rd ? 3 :
          s1_insn`rs1 == s4_rd ? 4 :
          s1_insn`rs1 == s5_rd ? 5 :
          /*                  */ 1;

   reg [`XMSB:0] s2_alu_op1_imm;
   always @(posedge clock)
     s2_alu_op1_imm
       <= s1_opcode == `LUI    ? 0 :
          s1_opcode == `AUIPC ||
          s1_opcode == `JALR  ||
          s1_opcode == `JAL    ? s1_pc : 'hX;

   always @(posedge clock)
     case (s2_alu_op1_src)
       0: s3_alu_op1 <= s2_alu_op1_imm;
       1: s3_alu_op1 <= s2_rs1_rf;
       2: s3_alu_op1 <= s3_wb_val;
       3: s3_alu_op1 <= s4_wb_val;
       4: s3_alu_op1 <= m3_wb_val;
       5: s3_alu_op1 <= s6_wb_val;
       7: s3_alu_op1 <= s2_csr_val;
       default: s3_alu_op1 <= 'hX;
     endcase

   always @(posedge clock)
     s2_alu_op2_src
       <= s1_op2_imm_use       ? 0 :
          !s1_use_rs2          ? 1 :
          s1_insn`rs2 == s2_rd ? 2 :
          s1_insn`rs2 == s3_rd ? 3 :
          s1_insn`rs2 == s4_rd ? 4 :
          s1_insn`rs2 == s5_rd ? 5 :
          /*                  */ 1;

   always @(posedge clock)
     case (s2_alu_op2_src)
       0: s3_alu_op2 <= s2_op2_imm;
       1: s3_alu_op2 <= s2_rs2_rf;
       2: s3_alu_op2 <= s3_wb_val;
       3: s3_alu_op2 <= s4_wb_val;
       4: s3_alu_op2 <= m3_wb_val;
       5: s3_alu_op2 <= s6_wb_val;
       default: s3_alu_op2 <= 'hX;
     endcase

   reg [2:0]     s2_rs1_src;
   reg [2:0]     s2_rs2_src;

   always @(posedge clock)
     s2_rs1_src
       <= !s1_use_rs1          ? 1 :
          s1_insn`rs1 == s2_rd ? 2 :
          s1_insn`rs1 == s3_rd ? 3 :
          s1_insn`rs1 == s4_rd ? 4 :
          s1_insn`rs1 == s5_rd ? 5 :
          /*                  */ 1;

   always @(posedge clock)
     case (s2_rs1_src)
       1: s3_rs1 <= s2_rs1_rf;
       2: s3_rs1 <= s3_wb_val;
       3: s3_rs1 <= s4_wb_val;
       4: s3_rs1 <= m3_wb_val;
       5: s3_rs1 <= s6_wb_val;
       default: s3_rs1 <= 'hX;
     endcase

   always @(posedge clock)
     s2_rs2_src
       <= !s1_use_rs2          ? 1 :
          s1_insn`rs2 == s2_rd ? 2 :
          s1_insn`rs2 == s3_rd ? 3 :
          s1_insn`rs2 == s4_rd ? 4 :
          s1_insn`rs2 == s5_rd ? 5 :
          /*                  */ 1;

   always @(posedge clock)
     case (s2_rs2_src)
       1: s3_rs2 <= s2_rs2_rf;
       2: s3_rs2 <= s3_wb_val;
       3: s3_rs2 <= s4_wb_val;
       4: s3_rs2 <= m3_wb_val;
       5: s3_rs2 <= s6_wb_val;
       default: s3_rs2 <= 'hX;
     endcase

   wire s3_alu_res_eq, s3_alu_res_lt, s3_alu_res_ltu;
   alu #(`XMSB+1) alu(s3_alu_sub, s3_alu_ashr, s3_alu_funct3, 1'd0,
                      s3_alu_op1, s3_alu_op2,
                      s3_wb_val, s3_alu_res_eq, s3_alu_res_lt, s3_alu_res_ltu);

   wire s3_cmp_lt = s3_insn`br_unsigned ? s3_alu_res_ltu : s3_alu_res_lt;
   wire s3_branch_taken = (s3_insn`br_rela ? s3_cmp_lt : s3_alu_res_eq) ^ s3_insn`br_negate;

   always @(posedge clock) begin
      s3_pc <= s2_pc;
      s3_insn <= s2_insn;
      s3_rd <= s2_valid ? s2_rd : 0;
      s3_sb_imm <= s2_sb_imm;
      s3_s_imm  <= s2_s_imm;
      s3_i_imm  <= s2_i_imm;
      s3_uj_imm <= s2_uj_imm;
      s3_csr_val<= s2_csr_val;
   end














   /* Commit stage */

   reg [   11:0] csr_mip_and_mie = 0;
   always @(posedge clock) csr_mip_and_mie <= csr_mip & csr_mie;

   reg              last_s3_valid = 0;
   reg              s4_flush = 0;
   wire             s4_valid = last_s3_valid;
   reg  [`XMSB:0]   s4_pc;
   reg  [   31:0]   s4_insn;
   reg  [    1:0]   s4_priv;

   reg              s4_restart = 1;
   reg  [`XMSB:0]   s4_restart_pc;

   reg  [    4:0]   s4_rd = 0;  // != 0 => WE. !valid => 0
   reg  [`XMSB:0]   s4_wb_val;
   reg  [`XMSB:0]   s4_rs1, s4_rs2;

   /* Updates to CSR state */
   reg  [`XMSB:0]   s4_csr_mcause;
   reg  [`XMSB:0]   s4_csr_mepc;
   reg  [`XMSB:0]   s4_csr_mstatus;
   reg  [`XMSB:0]   s4_csr_mtval;

   reg  [`XMSB:0]   s4_csr_sepc;
   reg  [`XMSB:0]   s4_csr_scause;
   reg  [`XMSB:0]   s4_csr_stval;
// reg  [`XMSB:0]   s4_csr_stvec;

   reg  [   11:0]   s4_csr_mideleg;
   reg  [   11:0]   s4_csr_medeleg;
   reg              s4_branch_taken = 0;
   reg              s4_csr_we;
   reg [`XMSB:0]    s4_csr_val;
   reg [`XMSB:0]    s4_csr_d;

   reg              s4_trap;
   reg [    3:0]    s4_trap_cause;
   reg [`XMSB:0]    s4_trap_val;
   reg              s4_intr;
   reg [    3:0]    s4_cause;
   reg              s4_deleg;
   reg [`XMSB:0]    s4_addr;

   reg [`PMSB:2]    s5_addr;
   wire [`XMSB:0]   m1_load_addr;
   always @(posedge clock) begin
      s4_branch_taken <= s3_branch_taken;
      s4_wb_val       <= s3_wb_val;
      s4_rd           <= s3_valid ? s3_rd : 0;
      s4_flush        <= 0;
      s4_restart      <= 0;
      s4_restart_pc   <= s3_pc + 4;
      s4_csr_val      <= s3_csr_val;
      s4_addr         <= s3_opcode == `LOAD || s3_opcode == `STORE ?
                         s3_rs1 + (s3_opcode == `LOAD ? s3_i_imm : s3_s_imm) : 0;

      if (s3_valid)
        case (s3_opcode)
          `LOAD: begin
             // XXX This is conservative, but I just want it passing for now
             // XXX Could be retimed by precomputing s4_addr - s3_s_imm and then just compare with s3_rs1
             if (s4_valid && s4_insn`opcode == `STORE && s4_addr[`PMSB:2] == m1_load_addr[`PMSB:2] ||
                 s5_valid && s5_insn`opcode == `STORE && s5_addr[`PMSB:2] == m1_load_addr[`PMSB:2]) begin
                s4_flush <= 1;
                s4_restart <= 1;
                s4_restart_pc <= s3_pc;
`ifndef QUIET
                $display("RESTART REASON: load-hit-store");
`endif
             end
          end

          `BRANCH: begin
             s4_restart <= s3_branch_taken;
             s4_restart_pc <= s3_pc + s3_sb_imm;
`ifndef QUIET
             if (s3_branch_taken)
               $display("RESTART REASON: conditional branch mispredicted");
`endif
          end

          `JALR: begin
             s4_restart <= 1;
             s4_restart_pc <= (s3_rs1 + s3_i_imm) & ~32'd1;
`ifndef QUIET
             $display("RESTART REASON: jalr mispredicted");
`endif
          end

          `JAL: begin
             s4_restart <= 1;
             s4_restart_pc <= s3_pc + s3_uj_imm;
`ifndef QUIET
             $display("RESTART REASON: jal mispredicted");
`endif
          end

          `SYSTEM: begin
             s4_restart <= 1;
             case (s3_insn`funct3)
               `PRIV:
                 case (s3_insn`imm11_0)
                   `ECALL, `EBREAK: begin
                      s4_restart_pc <= csr_mtvec;
`ifndef QUIET
                      $display("RESTART REASON: ecall or ebreak");
`endif
                   end
                   `MRET: begin
                      s4_restart_pc <= csr_mepc;
`ifndef QUIET
                      $display("RESTART REASON: mret");
`endif
                   end
                 endcase
               default: begin
`ifndef QUIET
                 $display("RESTART REASON: other system");
`endif
               end
             endcase
          end

          `MISC_MEM:
            case (s3_insn`funct3)
              `FENCE_I:
                begin
                   s4_restart <= 1;
`ifndef QUIET
                   $display("RESTART REASON: fence_i");
`endif
                end
            endcase
        endcase;

      /*
       * XXX This is awkward; with the exception below, everything for
       * s4 restart depends on s3.  However we do this to get more
       * time to determine the exceptions and we do want restarts as
       * early as possible otherwise.  Thus, s4_trap must also be
       * considered as having invalidated s4 for the next stage.
       */
      if (s4_trap || s4_intr) begin
`ifndef QUIET
         if (s4_trap_cause)
           $display("%5d  %x %x EXCEPTION %d", $time/10,
                    s4_pc, s4_insn, s4_trap_cause);
`endif
         s4_flush <= 1;
         s4_restart <= 1;
         s4_restart_pc <= csr_mtvec;
      end

      if (reset) begin
         s4_restart <= 1;
         s4_restart_pc <= `INIT_PC;
`ifndef QUIET
         $display("RESTART REASON: reset");
`endif
      end
   end

   always @(posedge clock) begin
      s4_pc    <= s3_pc;
      s4_insn  <= s3_insn;
      s4_rs1   <= s3_rs1;
      s4_rs2   <= s3_rs2;
      s4_branch_taken <= s3_branch_taken;
      s4_intr  <= csr_mip_and_mie != 0 && csr_mstatus`MIE;
   end

   /* Trap handling falls into things that can be determined at decode
    * time (static) and things we can't know until after execute
    * (dynamic).  The latter category is a timing path:
    * - interrupts (can be delayed arbitrarily so not an issue)
    * - misaligned cond. branch
    * - misaligned loads & stores
    *
    * The only one of these that must supress a register file write is
    * the misaligned load.
    */
   always @(*) begin
      s4_csr_we                         = 0;
      s4_priv                           = priv;
      s4_csr_mcause                     = csr_mcause;
      s4_csr_mepc                       = csr_mepc;
      s4_csr_mstatus                    = csr_mstatus;
      s4_csr_mtval                      = csr_mtval;

      s4_csr_scause                     = csr_scause;
      s4_csr_sepc                       = csr_sepc;
      s4_csr_stval                      = csr_stval;

      s4_csr_mideleg                    = csr_mideleg;
      s4_csr_medeleg                    = csr_medeleg;

      s4_trap                           = 0;
      s4_trap_cause                     = 0;
      s4_trap_val                       = 0;
      s4_csr_d                          = 'h X;

      case (s4_insn`opcode)
        `OP_IMM, `OP, `AUIPC, `LUI: ;

        // XXX Should compute ctl targets at end of decode and use that for misaligned fetch tests
        `BRANCH:
           if (s4_restart_pc[1] && s4_branch_taken) begin
              s4_trap                   = s4_valid;
              s4_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              s4_trap_val               = s4_restart_pc;
           end

        `JALR: begin
           if (s4_restart_pc[1]) begin
              s4_trap                   = s4_valid;
              s4_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              s4_trap_val               = s4_restart_pc;
           end
        end

        `JAL: begin
           if (s4_restart_pc[1]) begin
              s4_trap                   = s4_valid;
              s4_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              s4_trap_val               = s4_restart_pc;
           end
        end

        // XXX Do we _need_ to write CSR in s5?  Don't we have enough time to delay it a stage
        `SYSTEM: begin
           s4_csr_we                    = s4_valid;
           case (s4_insn`funct3)
             `CSRRS:  begin s4_csr_d    = s4_csr_val |  s4_rs1; if (s4_insn`rs1 == 0) s4_csr_we = 0; end
             `CSRRC:  begin s4_csr_d    = s4_csr_val &~ s4_rs1; if (s4_insn`rs1 == 0) s4_csr_we = 0; end
             `CSRRW:  begin s4_csr_d    =               s4_rs1; end
             `CSRRSI: begin s4_csr_d    = s4_csr_val |  {27'd0, s4_insn`rs1}; end
             `CSRRCI: begin s4_csr_d    = s4_csr_val &~ {27'd0, s4_insn`rs1}; end
             `CSRRWI: begin s4_csr_d    = $unsigned(s4_insn`rs1); end
             `PRIV: begin
                s4_csr_we               = 0;
                case (s4_insn`imm11_0)
                  `ECALL, `EBREAK: begin
                     s4_trap            = s4_valid;
                     s4_trap_cause      = s4_insn`imm11_0 == `ECALL
                                          ? `CAUSE_USER_ECALL | $unsigned(priv)
                                          : `CAUSE_BREAKPOINT;
                  end

                  `MRET: if (s4_valid) begin
                     s4_csr_mstatus`MIE = csr_mstatus`MPIE;
                     s4_csr_mstatus`MPIE= 1;
                     s4_priv            = csr_mstatus`MPP;
                     s4_csr_mstatus`MPP = `PRV_U;
                  end

                  `WFI: ; // XXX Should restart and block fetch until interrupt becomes pending

                  default: begin
                     s4_trap            = s4_valid;
                     s4_trap_cause      = `CAUSE_ILLEGAL_INSTRUCTION;
                  end
                endcase
             end
           endcase

           // Trap illegal CSRs accesses (ie. CSRs without permissions)
           case (s4_insn`funct3)
             `CSRRS, `CSRRC, `CSRRW, `CSRRSI, `CSRRCI, `CSRRWI:
               if (((s4_insn`imm11_0 & 12'hC00) == 12'hC00) && s4_csr_we || priv < s4_insn[31:30]) begin
                  s4_trap               = s4_valid;
                  s4_trap_cause         = `CAUSE_ILLEGAL_INSTRUCTION;
               end
           endcase
        end

        `MISC_MEM:
            case (s4_insn`funct3)
              `FENCE, `FENCE_I: ;
              default: begin
                 s4_trap                = s4_valid;
                 s4_trap_cause          = `CAUSE_ILLEGAL_INSTRUCTION;
              end
          endcase

        `LOAD: begin
           if (s4_insn == 0) begin
                s4_trap                 = s4_valid;
                s4_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
           end
           case (s4_insn`funct3)
             3, 6, 7: begin
                s4_trap                 = s4_valid;
                s4_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
             end
             default: begin
                s4_trap                 = s4_valid & s4_misaligned;
                s4_trap_cause           = `CAUSE_MISALIGNED_LOAD;
                s4_trap_val             = s4_addr;
             end
           endcase
        end

        `STORE: begin
           //store_addr              = s4_rs1 + s4_s_imm;
           case (s4_insn`funct3)
             3, 4, 5, 6, 7: begin
                s4_trap                 = s4_valid;
                s4_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
             end
             default: begin
                s4_trap                 = s4_valid & s4_misaligned;
                s4_trap_cause           = `CAUSE_MISALIGNED_STORE;
                s4_trap_val             = s4_addr;
             end
           endcase
        end

        default: begin
           s4_trap                      = s4_valid;
           s4_trap_cause                = `CAUSE_ILLEGAL_INSTRUCTION;
        end
      endcase

      if (s4_trap || s4_intr) begin
         if (s4_intr) begin
            // Awkward priority scheme
            s4_cause                    = (csr_mip_and_mie[1] ? 1 :
                                           csr_mip_and_mie[3] ? 3 :
                                           csr_mip_and_mie[5] ? 5 :
                                           csr_mip_and_mie[7] ? 7 :
                                           csr_mip_and_mie[9] ? 9 :
                                           11);
            s4_trap_val                 = 0;
         end else
            s4_cause                    = s4_trap_cause;

         s4_deleg = priv <= 1 && ((s4_intr ? csr_mideleg : csr_medeleg) >> s4_cause) & 1'd1;

         if (s4_deleg) begin
            s4_csr_scause[`XMSB]        = s4_intr;
            s4_csr_scause[`XMSB-1:0]    = s4_cause;
            s4_csr_sepc                 = s4_pc;
            s4_csr_stval                = s4_trap_val;
            s4_csr_mstatus`SPIE         = csr_mstatus`SIE;
            s4_csr_mstatus`SIE          = 0;
            s4_csr_mstatus`SPP          = priv; // XXX SPP is one bit whose two values are USER and SUPERVISOR?
            s4_priv                     = `PRV_S;
         end else begin
            s4_csr_mcause[`XMSB]        = s4_intr;
            s4_csr_mcause[`XMSB-1:0]    = s4_cause;
            s4_csr_mepc                 = s4_pc;
            s4_csr_mtval                = s4_trap_val;
            s4_csr_mstatus`MPIE         = csr_mstatus`MIE;
            s4_csr_mstatus`MIE          = 0;
            s4_csr_mstatus`MPP          = priv;
            s4_priv                     = `PRV_M;
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
      csr_mcycle                        <= csr_mcycle + 1;
      csr_mip[7]                        <= s5_timer_interrupt;

      priv                           <= s4_priv;
      csr_mcause                     <= s4_csr_mcause;
      csr_mepc                       <= s4_csr_mepc;
      csr_mstatus                    <= s4_csr_mstatus;
      csr_mtval                      <= s4_csr_mtval;
      csr_scause                     <= s4_csr_scause;
      csr_sepc                       <= s4_csr_sepc;
      csr_stval                      <= s4_csr_stval;

      csr_mideleg                    <= s4_csr_mideleg;
      csr_medeleg                    <= s4_csr_medeleg;
      csr_minstret                   <= csr_minstret + s5_valid;

      /* CSR write port (notice, this happens in EX) */
      if (s4_csr_we) begin
         case (s4_insn`imm11_0)
           `CSR_FCSR:      {csr_frm,csr_fflags} <= s4_csr_d[7:0];
           `CSR_FFLAGS:    csr_fflags   <= s4_csr_d[4:0];
           `CSR_FRM:       csr_frm      <= s4_csr_d[2:0];
           `CSR_MCAUSE:    csr_mcause   <= s4_csr_d;
//         `CSR_MCYCLE:    csr_mcycle   <= s4_csr_d;
           `CSR_MEPC:      csr_mepc     <= s4_csr_d & ~3;
           `CSR_MIE:       csr_mie      <= s4_csr_d;
//         `CSR_MINSTRET:  csr_instret  <= s4_csr_d;
           `CSR_MIP:       csr_mip      <= s4_csr_d & `CSR_MIP_WMASK | csr_mip & ~`CSR_MIP_WMASK;
           `CSR_MIDELEG:   csr_mideleg  <= s4_csr_d;
           `CSR_MEDELEG:   csr_medeleg  <= s4_csr_d;
           `CSR_MSCRATCH:  csr_mscratch <= s4_csr_d;
           `CSR_MSTATUS:   csr_mstatus  <= s4_csr_d & ~(15 << 13); // No FP or XS;
           `CSR_MTVEC:     csr_mtvec    <= s4_csr_d & ~1; // We don't support vectored interrupts
           `CSR_MTVAL:     csr_mtvec    <= s4_csr_d;

           `CSR_SCAUSE:    csr_scause   <= s4_csr_d;
           `CSR_SEPC:      csr_sepc     <= s4_csr_d;
           `CSR_STVEC:     csr_stvec    <= s4_csr_d & ~1; // We don't support vectored interrupts
           `CSR_STVAL:     csr_stvec    <= s4_csr_d;

           `CSR_PMPCFG0: ;
           `CSR_PMPADDR0: ;
`ifndef QUIET
           default:
             $display("                                            warning: unimplemented csr%x",
                      s4_insn`imm11_0);
`endif
         endcase
`ifndef QUIET
         $display("                                            csr%x <- %x",
                  s4_insn`imm11_0, s4_csr_d);
`endif
      end
   end




   reg s4_misaligned;
   always @(*)
     case (s4_insn`funct3 & 3)
       0: s4_misaligned =  0;               // Byte
       1: s4_misaligned =  s4_addr[  0]; // Half
       2: s4_misaligned = |s4_addr[1:0]; // Word
       3: s4_misaligned =  1'hX;
     endcase

   /* Load path */

   /* Store path */

   wire [`XMSB:0] s4_st_data;
   wire [    3:0] s4_st_mask;

   yarvi_st_align yarvi_st_align1
     (s4_insn`funct3, s4_addr[1:0], s4_rs2, s4_st_mask, s4_st_data);

   wire             s4_addr_in_mem = (s4_addr & (-1 << (`PMSB+1))) == 32'h80000000;
   wire [`PMSB-2:0] s4_wi = s4_addr[`PMSB:2];
   wire             s4_we = (s4_valid &&
                             !s4_flush &&
                             !s4_trap &&
                             !s4_intr &&
                             s4_insn`opcode == `STORE &&
                             s4_addr_in_mem);

   always @(posedge clock) begin
      if (s4_we & s4_st_mask[0]) data[s4_wi][ 7: 0] <= s4_st_data[ 7: 0];
      if (s4_we & s4_st_mask[1]) data[s4_wi][15: 8] <= s4_st_data[15: 8];
      if (s4_we & s4_st_mask[2]) data[s4_wi][23:16] <= s4_st_data[23:16];
      if (s4_we & s4_st_mask[3]) data[s4_wi][31:24] <= s4_st_data[31:24];
      if (s4_we & s4_st_mask[0]) code[s4_wi][ 7: 0] <= s4_st_data[ 7: 0];
      if (s4_we & s4_st_mask[1]) code[s4_wi][15: 8] <= s4_st_data[15: 8];
      if (s4_we & s4_st_mask[2]) code[s4_wi][23:16] <= s4_st_data[23:16];
      if (s4_we & s4_st_mask[3]) code[s4_wi][31:24] <= s4_st_data[31:24];
   end

   reg  [   63:0  ] mtime_future;
   reg              s5_timer_interrupt_future;
   reg              s5_valid = 0;
   reg  [`VMSB:0]   s5_pc;
   reg  [   31:0]   s5_insn;
   reg  [    4:0]   s5_rd = 0;
   reg  [`XMSB:0]   s5_wb_val;
   reg              s5_timer_interrupt;


   always @(posedge clock) begin
      s5_valid <= s4_valid & !s4_flush && !s4_trap && !s4_intr;
      s5_wb_val <= s4_wb_val;
   end

   /* Memory mapped io devices (only word-wide accesses are allowed) */
   always @(posedge clock) if (reset) begin
      mtime_future                      <= 0;
      mtimecmp                          <= 0;
   end else begin
      mtime_future                      <= mtime_future + 1; // XXX Yes, this is terrible
      s5_timer_interrupt_future         <= mtime > mtimecmp;
      mtime                             <= mtime_future;
      s5_timer_interrupt                <= s5_timer_interrupt_future;

      if (s4_valid && s4_insn`opcode == `STORE && (s4_addr & 32'h4FFFFFF3) == 32'h40000000)
        case (s4_addr[3:2])
          0: mtime[31:0]                <= s4_rs2;
          1: mtime[63:32]               <= s4_rs2;
          2: mtimecmp[31:0]             <= s4_rs2;
          3: mtimecmp[63:32]            <= s4_rs2;
        endcase
   end

`ifdef BEGIN_SIGNATURE
   reg  [`VMSB  :0] dump_addr;
`endif
   always @(posedge clock)
     if (!restart && s4_valid && s4_insn`opcode == `STORE && !s4_misaligned) begin
`ifndef QUIET
        if (!s4_addr_in_mem)
          $display("store %x -> [%x]/%x", s4_st_data, s4_addr, s4_st_mask);
`endif

`ifdef TOHOST
        if (s4_st_mask == 15 & s4_addr == 'h`TOHOST) begin
`ifndef QUIET
           $display("TOHOST = %d", s4_st_data);
`else
           $write("%c", s4_st_data);
`endif


`ifdef BEGIN_SIGNATURE
           $display("");
           $display("Signature Begin");
           for (dump_addr = 'h`BEGIN_SIGNATURE; dump_addr < 'h`END_SIGNATURE; dump_addr=dump_addr+4)
              $display("%x", data[dump_addr[`PMSB:2]]);
`endif
`ifndef KEEP_GOING
           $finish;
`endif
        end
`endif
     end


   always @(posedge clock) begin
      s5_rd   <= s4_valid ? s4_rd : 0;
      s5_pc   <= s4_pc;
      s5_insn <= s4_insn;
      s5_addr[`PMSB:2] <= s4_addr[`PMSB:2];
      if (|s5_rd & s5_valid) begin
         regs[s5_rd] <= m3_wb_val;
         //$display("%x %x r%1d %x", priv, s5_pc, s5_rd, m3_wb_val);
      end
   end


   // XXX going away soon
   reg  [`XMSB:0]   s6_wb_val;

   always @(posedge clock) begin
      s6_wb_val     <= m3_wb_val;

      retire_valid  <= s5_valid;
      retire_priv   <= priv;
      retire_pc     <= s5_pc;
      retire_insn   <= s5_insn;
      retire_rd     <= s5_rd;
      retire_wb_val <= m3_wb_val;
      debug         <= retire_wb_val;
   end

   // Module outputs
   assign           restart    = s4_restart;
   assign           restart_pc = s4_restart_pc;



//`ifdef SIMULATION
   /* Simulation-only */
   reg [31:0] i;
   initial begin
`ifndef QUIET
      $display("Initializing the %d B data memory", 1 << (`PMSB + 1));
`endif
      $readmemh(`INIT_MEM, code);
      $readmemh(`INIT_MEM, data);
      for (i = 0; i < 32; i = i + 1)
        regs[i[4:0]] = {26'd0,i[5:0]};
      regs[2] = 'h80000000 + (1 << (`PMSB + 1)); // XXX Total hack
   end
//`endif

`ifdef DISASSEMBLE
   yarvi_disass disass
     ( .clock  (clock)
     , .info   ({restart, 1'b1, s1_valid, s2_valid, s3_valid, s4_valid, s5_valid})
     , .valid  (s5_valid)
     , .prv    (priv)
     , .pc     (s5_pc)
     , .insn   (s5_insn)
     , .wb_rd  (s5_rd)
     , .wb_val (m3_wb_val));
`endif


   // Alternative memory pipeline
   assign         m1_load_addr = s3_rs1 + s3_i_imm; // Need full address
   reg  [`XMSB:0] m2_load_addr;
   reg  [    1:0] m3_load_addr;
   reg  [`XMSB:0] m2_memory_data;
   reg  [`XMSB:0] m3_memory_data;
/* verilator lint_off UNUSED */
   reg  [   31:0] m3_insn;
/* verilator lint_on UNUSED */
   wire [`XMSB:0] m3_wb_val;
   reg m3_load_addr_in_mem = 1;
   always @(posedge clock) begin
      m2_load_addr      <= m1_load_addr;
      m3_load_addr[1:0] <= m2_load_addr[1:0];
      m2_memory_data    <= data[m1_load_addr[`PMSB:2]];
      m3_insn           <= s4_insn;
      m3_memory_data    <= m2_memory_data;

      /* Memory mapped io devices (only word-wide accesses are allowed) */
      case (m2_load_addr[`PMSB:2])
        0: m3_mmio_data <= mtime[31:0]; // XXX  or uart
        1: m3_mmio_data <= mtime[63:32];
        2: m3_mmio_data <= mtimecmp[31:0];
        3: m3_mmio_data <= mtimecmp[63:32];
        default: m3_mmio_data <= 0;
      endcase
      m3_load_addr_in_mem
        <= (m2_load_addr & (-1 << (`PMSB+1))) == 32'h80000000;
   end
   reg [`XMSB:0] m3_mmio_data = 0;
   yarvi_ld_align yarvi_load_align_m
     (m3_insn`opcode != `LOAD, s5_wb_val,
      m3_insn`funct3, m3_load_addr[1:0],
      m3_load_addr_in_mem ? m3_memory_data : m3_mmio_data,
      m3_wb_val);

/* verilator lint_off UNUSED */
   wire same = m3_wb_val == s5_wb_val;

endmodule
