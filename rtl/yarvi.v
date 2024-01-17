// -----------------------------------------------------------------------
//
// YARVI RV32 in-order scalar core
//
// ISC License
//
// Copyright (C) 2014 - 2022  Tommy Thorn <tommy-github2@thorn.ws>
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
// -----------------------------------------------------------------------

// TO-DOs:
//
//  * Improve timing
//
//  * Convert memories to caches
//
//  * Tag every fetched instruction with seqno in program order (which
//    implies restoring it on restart).  Emit along with PC in traces.
//    Propagate even on stall/flush.  Idea is to correctly associate
//    bubbles with causes.
//
//  * add more accounting to enable "IPC stacks", that is, counting of
//    cycles wasted due to all the reasons above.
//
//  * Load-hit-store: investigate forwarding
//
//  * Load-use:
//    - store data can be forwarded from sub-word load only one cycle
//      penalty
//    - store data can be forwarded from full-word load with no penalty
//    - full-word loads can be forwarded one cycle earlier
//    - moving branch execution later in the pipeline with reduce or
//      eliminate load-use penalty (for a higher mispredict penalty)
//
//  * Improve timing
//    - looks like exception handling is slowing us down.
//      We probably need to insert a stage between EX and CM.
//    - The CSR update is a bottleneck => split CM into two stages
//    - The NPC mux could probably be slimmed
//    - re-investigate the alternative restart handling
//    - jalr misses can be made cheaper by precomputing pc-jr.imm
//      and checking the forwarded rs1 against that.
//
/*************************************************************************

This is the YARVI2 pipeline.

We have eight stages:

                          result forwarding
                        v---+----+----+----+

 s0   s1    s2    s3   s4   s5   s6   s7   s8
 PC | IF1 | IF2 | RF | DE | EX | CM | WB | -

  ^--- stall -----/
  ^----- pipeline restarts ------/

Showing the data loop and the two control loops.  There is a 7 cycle
mispredict penalty, same for load-hit-store.  Load has a 2 cycle
latency and can incur up to 2 stall cycles.

PC: PC generation/branch prediction
IF1: start instruction fetch
IF2: register fetched instruction
RF: read registers (and pre-decode)
DE: decode instruction and forward registers from later stages
EX: execute ALU instruction, compute branch conditions, load/store address
CM: Commit to the instruction or restart, start memory load
WB: write rf, store to memory,
    load way selection and data alignment/sign-extension

S8 isn't really a stage, but as we read registers in s3 any writes
happening in s7 wouldn't be visible yet so we'll have to forward from
s8.

Currently the pipeline can be restarted (and flushed) only from s6 and
causes the clear of all valid bits.

The pipeline might be invalidated or restarted for several reasons:
 - fetch mispredicted a branch and fed us the wrong instructions.
 - we need a value that is still being loaded from memory
 - instruction traps, like misaligned loads/stores
 - interrupts (which are taken in CM)

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
   reg  [    7:0] data0[(1 << (`PMSB-1)) - 1:0];
   reg  [    7:0] data1[(1 << (`PMSB-1)) - 1:0];
   reg  [    7:0] data2[(1 << (`PMSB-1)) - 1:0];
   reg  [    7:0] data3[(1 << (`PMSB-1)) - 1:0];
   reg  [    7:0] code0[(1 << (`PMSB-1)) - 1:0];
   reg  [    7:0] code1[(1 << (`PMSB-1)) - 1:0];
   reg  [    7:0] code2[(1 << (`PMSB-1)) - 1:0];
   reg  [    7:0] code3[(1 << (`PMSB-1)) - 1:0];
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




   // S0 - Branch Predition

   // Branch prediction:
   //
   // BTB caches control transfer logic (CTL) instructions which are:
   // 0. conditional branches ({BEQ,BNE,BLT,BGE,BLTU,BGEU),
   // 1. calls (JAL with rd in {r1,r5}),
   // 2. returns (JALR with rs1 in {r1,r5} and rd=r0},
   // 3. jumps (JAL with rd not in {r1,r5}), or
   // 4. indirect jumps (JALR otherwise).
   //
   // We embed the bimodal predictor in the BTB and use a clever
   // encoding to make the critical mux path cheaper:
   //
   //       000 branch-strongly-not-taken
   //       001 branch-weakly-not-taken
   //       010 branch-weakly-taken
   //       011 branch-strongly-taken
   //       10x return
   //       110 jump
   //       111 call
   //
   //       case (s0_btb_type[2:1] & {2{btb_hit))
   //       0:    npc = pc_sequential
   //       1, 3: npc = btb-target;
   //       2:    npc = ras0;
   //       endcase
   //
   // That is, the LSB is not relevant for the mux but only for the
   // RAS update and branch weight.

`define BTB_TYPE_BR_S_N 3'd0
`define BTB_TYPE_BR_W_N 3'd1
`define BTB_TYPE_BR_W_T 3'd2
`define BTB_TYPE_BR_S_T 3'd3
`define BTB_TYPE_RETURN 3'd4
`define BTB_TYPE_JUMP   3'd6
`define BTB_TYPE_CALL   3'd7

   // The BTB stores the type and part of the target address.  The
   // remaining bits are copied from the PC (we could do better, eg.
   // use a delta if timing allows).
   //
   // The BTB also stores a partial tag.  For timing, the BTB is
   // directly mapped.
   //
   // Parameters:
   // - entries in the BTB (thus, the width of the index)
   // - width of target information
   // - width of tag

`define BTB_INDEX_MSB   9 // 1,024 entries
`define BTB_TAG_MSB     4 // 5 bit tag, 5 + 10 = 15, 32 Kinsn coverage
`define BTB_TARGET_MSB 14 // 2¹⁵ insn = 128 KiB coverage
   // 1K * (15 + 5 + 2) = 22 Kib

   reg [              2:0] btb_type[(2 << `BTB_INDEX_MSB) - 1:0];
   reg [`BTB_TAG_MSB   :0] btb_tag[(2 << `BTB_INDEX_MSB) - 1:0];
   reg [`BTB_TARGET_MSB:0] btb_target[(2 << `BTB_INDEX_MSB) - 1:0];
   reg [`VMSB          :0] ras0 = 'h110, ras1 = 'h220, ras2 = 'h440;

`define YAGS_TAG_MSB    5 // 6-bit tags
`define YAGS_INDEX_MSB 11 // 12-bit index, 4096 entries

   // YAGS corrector
   reg [`YAGS_TAG_MSB  :0] yags_tag[(2 << `YAGS_INDEX_MSB) - 1:0];
   reg [              1:0] yags_direction[(2 << `YAGS_INDEX_MSB) - 1:0];
   reg [`YAGS_INDEX_MSB:0] br_history = 0;

   wire                    restart;
   wire [`VMSB         :0] restart_pc;
   wire                    s3_stall;

   reg                     btb_update = 0;
   reg [`BTB_INDEX_MSB :0] btb_update_idx;
   reg [              2:0] btb_update_type;
   reg [`BTB_TAG_MSB   :0] btb_update_tag;
   reg [`BTB_TARGET_MSB:0] btb_update_target;

   reg                     yags_update = 0;
   reg [`YAGS_INDEX_MSB:0] yags_update_idx;
   reg [              1:0] yags_update_direction;
   reg [`YAGS_TAG_MSB  :0] yags_update_tag;

   reg                     s0_yags_hit;
   reg [`YAGS_INDEX_MSB:0] s0_yags_idx;
   reg [`YAGS_TAG_MSB  :0] s0_yags_tag;
   reg [              1:0] s0_yags_dir;

   reg  [`VMSB         :0] s0_pc;
   reg  [`VMSB         :0] s0_npc;
   reg [              2:0] s0_btb_type;
   reg [`BTB_TAG_MSB   :0] s0_btb_tag;
   reg [`BTB_TARGET_MSB:0] s0_btb_target;
   reg                     s0_btb_hit;

   reg [              2:0] s0_prediction;

   always @(*) begin
      s0_btb_hit  = s0_pc[`BTB_TAG_MSB+`BTB_INDEX_MSB+3:`BTB_INDEX_MSB+3]    == s0_btb_tag;
      s0_yags_hit = s0_pc[`YAGS_TAG_MSB+`YAGS_INDEX_MSB+3:`YAGS_INDEX_MSB+3] == s0_yags_tag;

      casez ({s0_btb_hit,s0_btb_type,s0_yags_hit,s0_yags_dir})
        // BTB says return => ignore YAGS and follow RAS
        {1'd1,`BTB_TYPE_RETURN, 3'd?}: begin
          s0_prediction = `BTB_TYPE_RETURN;
          s0_npc = ras0;
        end

        // BTB says jump => ignore YAGS and follow BTB target
        {1'd1,`BTB_TYPE_JUMP, 3'd?}: begin
          s0_prediction = `BTB_TYPE_JUMP;
          s0_npc = {s0_pc[`XMSB:`BTB_TARGET_MSB+3],s0_btb_target,2'd0};
        end

        // BTB says call => ignore YAGS and follow BTB target
        {1'd1,`BTB_TYPE_CALL, 3'd?}: begin
          s0_prediction = `BTB_TYPE_CALL;
          s0_npc = {s0_pc[`XMSB:`BTB_TARGET_MSB+3],s0_btb_target,2'd0};
        end

        // BTB says taken and YAGS miss => follow BTB target
        {1'd1,`BTB_TYPE_BR_S_T, 1'd0,2'd?}, {1'd1,`BTB_TYPE_BR_W_T, 1'd0,2'd?}: begin
           s0_prediction = `BTB_TYPE_BR_W_T;
           s0_npc = {s0_pc[`XMSB:`BTB_TARGET_MSB+3],s0_btb_target,2'd0};
        end

        // BTB says it's a branch and YAGS says taken => follow BTB target
        {1'd1,3'b0??, 1'd1, 2'b1?}: begin
          s0_prediction = `BTB_TYPE_BR_W_T;
          s0_npc = {s0_pc[`XMSB:`BTB_TARGET_MSB+3],s0_btb_target,2'd0};
        end

        // Otherwise sequential
        default: begin
          s0_prediction = `BTB_TYPE_BR_W_N;
          s0_npc = s0_pc + 4;
        end
      endcase


      // XXX It should be possible to fold the reset case into the ras0 case
      // and also stall if using skid buffers
      if (s3_stall)
        s0_npc = s0_pc;

      if (restart)
        s0_npc = restart_pc;
   end

   reg s0_restart = 1;
   always @(posedge clock) begin
      s0_restart    <= restart;
      s0_pc         <= s0_npc;
      s0_btb_tag    <= btb_tag[s0_npc[`BTB_INDEX_MSB+2:2]];
      s0_btb_target <= btb_target[s0_npc[`BTB_INDEX_MSB+2:2]];
      s0_btb_type   <= btb_type[s0_npc[`BTB_INDEX_MSB+2:2]];

      s0_yags_idx   <= s0_pc[`YAGS_INDEX_MSB+2:2] ^ br_history;
      s0_yags_tag   <= yags_tag[s0_pc[`YAGS_INDEX_MSB+2:2] ^ br_history];
      s0_yags_dir   <= yags_direction[s0_pc[`YAGS_INDEX_MSB+2:2] ^ br_history];

      if (yags_update) begin
         yags_tag[yags_update_idx] <= yags_update_tag;
         yags_direction[yags_update_idx] <= yags_update_direction;
`ifndef QUIET
         $display("UPDATE_: YAGS[%x]=%x:%d -> %x:%d", yags_update_idx,
                  yags_tag[yags_update_idx],
                  yags_direction[yags_update_idx],
                  yags_update_tag,
                  yags_update_direction);
`endif
      end

      if (restart) begin
         br_history <= rbr_history;
         ras0 <= rras0;
         ras1 <= rras1;
         ras2 <= rras2;
`ifndef QUIET
         $display("           RAS now: %x %x %x History %x", rras0, rras1, rras2, rbr_history);
`endif
      end

      if (!s3_stall & !restart & s0_btb_hit)
         case (s0_prediction)
           `BTB_TYPE_CALL: begin
`ifndef QUIET
              $display("PREDICT: %x (%d) CALL to %x RAS: %x %x %x", s0_pc, s0_pc[`BTB_INDEX_MSB+2:2], s0_npc,
                       s0_pc + 4, ras0, ras1);
`endif
              // Old ras2 lost
              ras2 <= ras1;
              ras1 <= ras0;
              ras0 <= s0_pc + 4;
           end
           `BTB_TYPE_RETURN: begin
`ifndef QUIET
              $display("PREDICT: %x (%d) RETURN to %x RAS: %x %x", s0_pc, s0_pc[`BTB_INDEX_MSB+2:2], s0_npc, ras1, ras2);
`endif
              ras0 <= ras1;
              ras1 <= ras2;
              // keep ras2
              ras2 <= 0; // XXX just to make debugging easier
           end
           `BTB_TYPE_JUMP: begin
`ifndef QUIET
              $display("PREDICT: %x (%d) JUMP to %x", s0_pc, s0_pc[`BTB_INDEX_MSB+2:2], s0_npc);
`endif
           end
           `BTB_TYPE_BR_S_T, `BTB_TYPE_BR_W_T: begin
`ifndef QUIET
              if (s0_yags_hit)
                $display("PREDICT: %x (%d) YAGS[%x]=%x:%x said %s TAKEN BRANCH to %x", s0_pc, s0_pc[`BTB_INDEX_MSB+2:2],
                         s0_yags_idx, s0_yags_tag, s0_yags_dir,
                         s0_btb_type == `BTB_TYPE_BR_S_T ? "STRONGLY" : "WEAKLY", s0_npc);
              else
                $display("PREDICT: %x (%d) BM said %s TAKEN BRANCH to %x", s0_pc, s0_pc[`BTB_INDEX_MSB+2:2],
                         s0_btb_type == `BTB_TYPE_BR_S_T ? "STRONGLY" : "WEAKLY", s0_npc);
`endif
              br_history <= (br_history << 1) | 1'b1;
           end
           `BTB_TYPE_BR_S_N, `BTB_TYPE_BR_W_N: begin
`ifndef QUIET
              if (s0_yags_hit)
                $display("PREDICT: %x (%d) YAGS[%x] said %s TAKEN BRANCH to %x", s0_pc, s0_pc[`BTB_INDEX_MSB+2:2],
                         s0_yags_idx,
                         s0_btb_type == `BTB_TYPE_BR_S_T ? "STRONGLY" : "WEAKLY", s0_npc);
`endif
              br_history <= (br_history << 1) | 1'b0;
           end
           default: begin /* can't happen */ end
         endcase

      if (btb_update) begin
         btb_type[btb_update_idx] <= btb_update_type;
         btb_tag[btb_update_idx] <= btb_update_tag;
         btb_target[btb_update_idx] <= btb_update_target;

`ifndef QUIET
         if (btb_update_type == `BTB_TYPE_RETURN)
           $display("UPDATE_: %x (%d) RETURN",
                    {s7_pc[`XMSB:`BTB_TAG_MSB+`BTB_INDEX_MSB+4],btb_update_tag,btb_update_idx,2'd0},
                    btb_update_idx);
         else
           $display("UPDATE_: %x (%d) %-s to %x",
                    {s7_pc[`XMSB:`BTB_TAG_MSB+`BTB_INDEX_MSB+4],btb_update_tag,btb_update_idx,2'd0},
                    btb_update_idx,
                    btb_update_type == `BTB_TYPE_CALL ? "CALL" :
                    btb_update_type == `BTB_TYPE_JUMP ? "JUMP" :
                    btb_update_type == `BTB_TYPE_BR_S_T ? "BR-strong-taken" :
                    btb_update_type == `BTB_TYPE_BR_S_N ? "BR-strong-nontaken" :
                    btb_update_type == `BTB_TYPE_BR_W_T ? "BR-weak-taken" :
                    btb_update_type == `BTB_TYPE_BR_W_N ? "BR-weak-nontaken" : "???",
                    {s7_pc[`XMSB:`BTB_TARGET_MSB+3],btb_update_target,2'd0});
`endif
      end
   end



   // S1 - Start instruction fetch
   wire                    s1_valid = !s0_restart & !restart;
   reg [`VMSB          :0] s1_pc;
   reg [`VMSB          :0] s1_npc;
   reg [31             :0] s1_insn;
   reg [              2:0] s1_btb_type;
   reg                     s1_btb_hit;
   reg [`YAGS_INDEX_MSB:0] s1_yags_idx;
   reg                     s1_yags_hit;
   reg [1              :0] s1_yags_dir;
   always @(posedge clock) if (!s3_stall | restart) begin
      s1_pc         <= s0_pc;
      s1_npc        <= s0_npc;
      s1_insn       <= {code3[s0_pc[`PMSB:2]],code2[s0_pc[`PMSB:2]],code1[s0_pc[`PMSB:2]],code0[s0_pc[`PMSB:2]]};
      s1_btb_type   <= s0_btb_type;
      s1_btb_hit    <= s0_btb_hit;
      s1_yags_idx   <= s0_yags_idx;
      s1_yags_hit   <= s0_yags_hit;
      s1_yags_dir   <= s0_yags_dir;
   end



   // S2 - Register fetched instruction
   reg                     s2_valid_r = 0;
   wire                    s2_valid = s2_valid_r & !restart;
   reg [`VMSB          :0] s2_pc;
   reg [`VMSB          :0] s2_npc;
   reg [31             :0] s2_insn;
   reg [              2:0] s2_btb_type;
   reg                     s2_btb_hit;
   reg [`YAGS_INDEX_MSB:0] s2_yags_idx;
   reg                     s2_yags_hit;
   reg [1              :0] s2_yags_dir;
   always @(posedge clock) if (!s3_stall | restart) begin
      s2_valid_r    <= s1_valid;
      s2_pc         <= s1_pc;
      s2_npc        <= s1_npc;
      s2_insn       <= s1_insn;
      s2_btb_type   <= s1_btb_type;
      s2_btb_hit    <= s1_btb_hit;
      s2_yags_idx   <= s1_yags_idx;
      s2_yags_hit   <= s1_yags_hit;
      s2_yags_dir   <= s1_yags_dir;
   end



   // S3 - RF, stall if needed, read registers
   reg                     s3_valid_r = 0;
   wire                    s3_valid = s3_valid_r & !restart;
   reg [`XMSB          :0] s3_pc;
   reg [`XMSB          :0] s3_npc;
   reg [   31:          0] s3_insn;
   reg [              2:0] s3_btb_type;
   reg                     s3_btb_hit;
   reg [`YAGS_INDEX_MSB:0] s3_yags_idx;
   reg                     s3_yags_hit;
   reg [1              :0] s3_yags_dir;
   always @(posedge clock) begin
      s3_valid_r     <= s2_valid;
   end
   always @(posedge clock) if (!s3_stall | restart) begin
      s3_pc          <= s2_pc;
      s3_npc         <= s2_npc;
      s3_insn        <= s2_insn;
      s3_btb_type    <= s2_btb_type;
      s3_btb_hit     <= s2_btb_hit;
      s3_yags_idx    <= s2_yags_idx;
      s3_yags_hit    <= s2_yags_hit;
      s3_yags_dir    <= s2_yags_dir;
   end

   wire [`XMSB-12:0] s3_sext12 = {(`XMSB-11){s3_insn[31]}};
   wire [`XMSB-20:0] s3_sext20 = {(`XMSB-19){s3_insn[31]}};
   wire [`XMSB   :0] s3_i_imm  = {s3_sext12, s3_insn`funct7, s3_insn`rs2};
   wire [`XMSB   :0] s3_sb_imm = {s3_sext12, s3_insn[7], s3_insn[30:25], s3_insn[11:8], 1'd0};
   wire [`XMSB   :0] s3_s_imm  = {s3_sext12, s3_insn`funct7, s3_insn`rd};
   wire [`XMSB   :0] s3_uj_imm = {s3_sext20, s3_insn[19:12], s3_insn[20], s3_insn[30:21], 1'd0};



   wire             s3_use_rs1, s3_use_rs2;
   wire [    4:0]   s3_rd;

   /* NB: r0 is not considered used */
   yarvi_dec_reg_usage yarvi_dec_reg_usage_inst0(s3_valid, s3_insn,
                                                 s3_use_rs1, s3_use_rs2, s3_rd);

   wire [    4:0]   s3_opcode = s3_insn`opcode;
   reg              s3_op2_imm_use;
   reg  [`XMSB:0]   s3_op2_imm;
   always @(*)
     {s3_op2_imm_use, s3_op2_imm}
                 = s3_insn`opcode == `AUIPC ||
                   s3_insn`opcode == `LUI    ? {1'd1, s3_insn[31:12], 12'd 0} :
                   s3_insn`opcode == `JALR  ||
                   s3_insn`opcode == `JAL    ? {1'd1, 32'd 4}              :
                   s3_insn`opcode == `SYSTEM ? {1'd1, 32'd 0}              :
                   s3_insn`opcode == `OP_IMM ||
                   s3_insn`opcode == `OP_IMM_32 ||
                   s3_insn`opcode == `LOAD   ? {1'd1, s3_i_imm}            :
                   s3_insn`opcode == `STORE  ? {1'd1, s3_s_imm}            :
                                       0;
   assign s3_stall
     = s3_use_rs1 && s3_insn`rs1 == s4_rd && s4_insn`opcode == `LOAD ||
       s3_use_rs2 && s3_insn`rs2 == s4_rd && s4_insn`opcode == `LOAD ||
       s3_use_rs1 && s3_insn`rs1 == s5_rd && s5_insn`opcode == `LOAD ||
       s3_use_rs2 && s3_insn`rs2 == s5_rd && s5_insn`opcode == `LOAD;



   // S4 - Decode and forward operands
   reg                     s4_valid_r = 0;
   wire                    s4_valid = s4_valid_r & !restart & !s4_stall;
   reg                     s4_stall = 0;
   reg [`XMSB          :0] s4_pc;
   reg [`XMSB          :0] s4_npc;
   reg [   31          :0] s4_insn;
   reg [    4          :0] s4_rd;
   reg [`XMSB          :0] s4_rs1_rf;
   reg [`XMSB          :0] s4_rs2_rf;
   reg [`XMSB          :0] s4_op2_imm;
   reg [              2:0] s4_btb_type;
   reg                     s4_btb_hit;
   reg [`YAGS_INDEX_MSB:0] s4_yags_idx;
   reg                     s4_yags_hit;
   reg [1              :0] s4_yags_dir;

   // Possible targets for normal execution:
   // - statically determined (+4 or jump target)
   // - semi-static (conditional branch)
   // - dynamic (indirect)
   reg  [`XMSB:0] s4_insn_target;
   reg  [`XMSB:0] s4_br_target;
   always @(posedge clock) begin
      s4_valid_r     <= s3_valid;
      s4_stall       <= s3_stall;
      s4_pc          <= s3_pc;
      s4_npc         <= s3_npc;
      s4_insn        <= s3_insn;
      s4_rd          <= s3_stall ? 0 : s3_rd;
      s4_rs1_rf      <= regs[s3_insn`rs1];
      s4_rs2_rf      <= regs[s3_insn`rs2];
      s4_op2_imm     <= s3_op2_imm;
      s4_btb_type    <= s3_btb_type;
      s4_btb_hit     <= s3_btb_hit;
      s4_yags_idx    <= s3_yags_idx;
      s4_yags_hit    <= s3_yags_hit;
      s4_yags_dir    <= s3_yags_dir;
      s4_br_target   <= s3_pc + s3_sb_imm;
      s4_insn_target <= s3_pc + 4;
      case (s3_insn`opcode)
        `JAL: s4_insn_target <= s3_pc + s3_uj_imm;
      endcase
   end

   wire [`XMSB-12:0] s4_sext12 = {(`XMSB-11){s4_insn[31]}};
   wire [`XMSB   :0] s4_i_imm  = {s4_sext12, s4_insn`funct7, s4_insn`rs2};
   wire [`XMSB   :0] s4_s_imm  = {s4_sext12, s4_insn`funct7, s4_insn`rd};
   wire [       4:0] s4_opcode = s4_insn`opcode;
   reg  [`XMSB   :0] s4_csr_val;
   always @(posedge clock)
     case (s3_insn`imm11_0)
       // Standard User R/W
       `CSR_FFLAGS:       s4_csr_val <= {27'd0, csr_fflags};
       `CSR_FRM:          s4_csr_val <= {29'd0, csr_frm};
       `CSR_FCSR:         s4_csr_val <= {24'd0, csr_frm, csr_fflags};

       `CSR_MSTATUS:      s4_csr_val <= csr_mstatus;
       `CSR_MISA:         s4_csr_val <= (32'd 2 << 30) | (32'd 1 << ("I"-"A"));
       `CSR_MIE:          s4_csr_val <= {{(`XMSB-11){1'd0}}, csr_mie};
       `CSR_MTVEC:        s4_csr_val <= csr_mtvec;

       `CSR_MSCRATCH:     s4_csr_val <= csr_mscratch;
       `CSR_MEPC:         s4_csr_val <= csr_mepc;
       `CSR_MCAUSE:       s4_csr_val <= csr_mcause;
       `CSR_MTVAL:        s4_csr_val <= csr_mtval;
       `CSR_MIP:          s4_csr_val <= {{(`XMSB-11){1'd0}}, csr_mip};
       `CSR_MIDELEG:      s4_csr_val <= {{(`XMSB-11){1'd0}}, csr_mideleg};
       `CSR_MEDELEG:      s4_csr_val <= {{(`XMSB-11){1'd0}}, csr_medeleg};

       `CSR_MCYCLE:       s4_csr_val <= csr_mcycle;
       `CSR_MINSTRET:     s4_csr_val <= csr_minstret;

       `CSR_PMPCFG0:      s4_csr_val <= 0;
       `CSR_PMPADDR0:     s4_csr_val <= 0;

       // Standard Machine RO
       `CSR_MVENDORID:    s4_csr_val <= `VENDORID_YARVI;
       `CSR_MARCHID:      s4_csr_val <= 0;
       `CSR_MIMPID:       s4_csr_val <= 0;
       `CSR_MHARTID:      s4_csr_val <= 0;

       `CSR_SEPC:         s4_csr_val <= csr_sepc;
       `CSR_SCAUSE:       s4_csr_val <= csr_scause;
       `CSR_STVAL:        s4_csr_val <= csr_stval;
       `CSR_STVEC:        s4_csr_val <= csr_stvec;

       `CSR_CYCLE:        s4_csr_val <= csr_mcycle;
       `CSR_INSTRET:      s4_csr_val <= csr_minstret;

        default:          s4_csr_val <= 0;
     endcase

   reg [2:0]     s4_alu_op1_src;
   reg [2:0]     s4_alu_op2_src;

   always @(posedge clock)
     s4_alu_op1_src
       <= s3_opcode == `LUI   ||
          s3_opcode == `AUIPC ||
          s3_opcode == `JALR  ||
          s3_opcode == `JAL    ? 0 :
          s3_opcode == `SYSTEM ? 7 :
          !s3_use_rs1          ? 1 :
          s3_insn`rs1 == s4_rd ? 2 :
          s3_insn`rs1 == s5_rd ? 3 :
          s3_insn`rs1 == s6_rd ? 4 :
          s3_insn`rs1 == s7_rd ? 5 :
          /*                  */ 1;

   reg [`XMSB:0] s4_alu_op1_imm;
   always @(posedge clock)
     s4_alu_op1_imm
       <= s3_opcode == `LUI    ? 0 :
          s3_opcode == `AUIPC ||
          s3_opcode == `JALR  ||
          s3_opcode == `JAL    ? s3_pc : 'hX;



   // S5 - Execute all ALU
   reg                      s5_valid_r = 0;
   wire                     s5_valid = s5_valid_r & !restart;
   reg  [`XMSB          :0] s5_pc;
   reg  [`XMSB          :0] s5_npc;
   reg  [   31          :0] s5_insn;
   reg  [    4          :0] s5_rd;
   wire [`XMSB          :0] s5_wb_val;
   wire [    4          :0] s5_opcode = s5_insn`opcode;
   reg  [`XMSB          :0] s5_s_imm;
   reg  [`XMSB          :0] s5_i_imm;
   reg  [`XMSB          :0] s5_rs1;
   reg  [`XMSB          :0] s5_rs2;
   reg  [`XMSB          :0] s5_csr_val;
   reg  [`XMSB          :0] s5_insn_target = 0;
   reg  [`XMSB          :0] s5_pc_insn_miss = 0;
   reg  [`XMSB          :0] s5_br_target;
   reg  [`XMSB          :0] s5_br_target_miss;
   reg  [`XMSB          :0] s5_jalr_target;
   reg  [`XMSB          :0] s5_jalr_target_miss;
   reg  [`XMSB          :0] s5_alu_op1, s5_alu_op2;
   reg  [              2:0] s5_btb_type;
   reg                      s5_btb_hit;
   reg  [`YAGS_INDEX_MSB:0] s5_yags_idx;
   reg                      s5_yags_hit;
   reg  [              1:0] s5_yags_dir;

   always @(posedge clock) begin
      s5_valid_r          <= s4_valid;
      s5_insn_target      <= s4_insn_target;
      s5_pc_insn_miss     <= s4_insn_target != s4_npc;
      s5_br_target        <= s4_br_target;
      s5_br_target_miss   <= s4_br_target != s4_npc;
      s5_btb_type         <= s4_btb_type;
      s5_btb_hit          <= s4_btb_hit;
      s5_yags_idx         <= s4_yags_idx;
      s5_yags_hit         <= s4_yags_hit;
      s5_yags_dir         <= s4_yags_dir;
   end

   reg s5_alu_sub = 0;
   always @(posedge clock)
     s5_alu_sub <= (s4_opcode == `OP     && s4_insn`funct3 == `ADDSUB && s4_insn[30] ||
                    s4_opcode == `OP     && s4_insn`funct3 == `SLT                   ||
                    s4_opcode == `OP     && s4_insn`funct3 == `SLTU                  ||
                    s4_opcode == `OP_IMM && s4_insn`funct3 == `SLT                   ||
                    s4_opcode == `OP_IMM && s4_insn`funct3 == `SLTU                  ||
                    s4_opcode == `BRANCH);

   reg s5_alu_ashr = 0;
   always @(posedge clock)
     s5_alu_ashr <= s4_insn[30];

   reg [2:0] s5_alu_funct3 = 0;
   always @(posedge clock)
     s5_alu_funct3 <= (s4_opcode == `OP        ||
                       s4_opcode == `OP_IMM    ||
                       s4_opcode == `OP_IMM_32 ? s4_insn`funct3 : `ADDSUB);

   always @(posedge clock)
     case (s4_alu_op1_src)
       0: s5_alu_op1 <= s4_alu_op1_imm;
       1: s5_alu_op1 <= s4_rs1_rf;
       2: s5_alu_op1 <= s5_wb_val;
       3: s5_alu_op1 <= s6_wb_val;
       4: s5_alu_op1 <= m3_wb_val;
       5: s5_alu_op1 <= s8_wb_val;
       7: s5_alu_op1 <= s4_csr_val;
       default: s5_alu_op1 <= 'hX;
     endcase

   always @(posedge clock)
     s4_alu_op2_src
       <= s3_op2_imm_use       ? 0 :
          !s3_use_rs2          ? 1 :
          s3_insn`rs2 == s4_rd ? 2 :
          s3_insn`rs2 == s5_rd ? 3 :
          s3_insn`rs2 == s6_rd ? 4 :
          s3_insn`rs2 == s7_rd ? 5 :
          /*                  */ 1;

   always @(posedge clock)
     case (s4_alu_op2_src)
       0: s5_alu_op2 <= s4_op2_imm;
       1: s5_alu_op2 <= s4_rs2_rf;
       2: s5_alu_op2 <= s5_wb_val;
       3: s5_alu_op2 <= s6_wb_val;
       4: s5_alu_op2 <= m3_wb_val;
       5: s5_alu_op2 <= s8_wb_val;
       default: s5_alu_op2 <= 'hX;
     endcase

   reg [2:0]     s4_rs1_src;
   reg [2:0]     s4_rs2_src;

   always @(posedge clock)
     s4_rs1_src
       <= !s3_use_rs1          ? 1 :
          s3_insn`rs1 == s4_rd ? 2 :
          s3_insn`rs1 == s5_rd ? 3 :
          s3_insn`rs1 == s6_rd ? 4 :
          s3_insn`rs1 == s7_rd ? 5 :
          /*                  */ 1;

   always @(posedge clock)
     case (s4_rs1_src)
       1: s5_rs1 <= s4_rs1_rf;
       2: s5_rs1 <= s5_wb_val;
       3: s5_rs1 <= s6_wb_val;
       4: s5_rs1 <= m3_wb_val;
       5: s5_rs1 <= s8_wb_val;
       default: s5_rs1 <= 'hX;
     endcase

   always @(posedge clock)
     s4_rs2_src
       <= !s3_use_rs2          ? 1 :
          s3_insn`rs2 == s4_rd ? 2 :
          s3_insn`rs2 == s5_rd ? 3 :
          s3_insn`rs2 == s6_rd ? 4 :
          s3_insn`rs2 == s7_rd ? 5 :
          /*                  */ 1;

   always @(posedge clock)
     case (s4_rs2_src)
       1: s5_rs2 <= s4_rs2_rf;
       2: s5_rs2 <= s5_wb_val;
       3: s5_rs2 <= s6_wb_val;
       4: s5_rs2 <= m3_wb_val;
       5: s5_rs2 <= s8_wb_val;
       default: s5_rs2 <= 'hX;
     endcase

   wire s5_alu_res_eq, s5_alu_res_lt, s5_alu_res_ltu;
   /* verilator lint_off UNUSEDSIGNAL */
   wire [`XMSB:0] s5_sum; // XXX Not used currently but could be the load address
   alu #(`XMSB+1) alu(.sub(s5_alu_sub),
                      .ashr(s5_alu_ashr),
                      .funct3(s5_alu_funct3),
                      .w(1 'd 0),
                      .op1(s5_alu_op1),
                      .op2(s5_alu_op2),
                      .result(s5_wb_val),
                      .sum(s5_sum),
                      .eq(s5_alu_res_eq),
                      .lt(s5_alu_res_lt),
                      .ltu(s5_alu_res_ltu));
   /* verilator lint_on UNUSEDSIGNAL */

   wire s5_cmp_lt = s5_insn`br_unsigned ? s5_alu_res_ltu : s5_alu_res_lt;
   wire s5_branch_taken = (s5_insn`br_rela ? s5_cmp_lt : s5_alu_res_eq) ^ s5_insn`br_negate;

   always @(posedge clock) begin
      s5_pc      <= s4_pc;
      s5_npc     <= s4_npc;
      s5_insn    <= s4_insn;
      s5_rd      <= s4_valid ? s4_rd : 0;
      s5_s_imm   <= s4_s_imm;
      s5_i_imm   <= s4_i_imm;
      s5_csr_val <= s4_csr_val;
   end

   always @(*) begin
      s5_jalr_target      = (s5_rs1 + s5_i_imm) & ~32'd1;
      s5_jalr_target_miss = ((s5_rs1 + s5_i_imm) & ~32'd1) != s5_npc;
   end



   // S6 - Commit or restart, calculate where restart from if needed
   reg [   11:0] csr_mip_and_mie = 0;
   always @(posedge clock) csr_mip_and_mie <= csr_mip & csr_mie;

   reg              s6_valid_r = 0;
   reg              s6_flush = 0;
   wire             s6_valid = s6_valid_r;
   reg  [`XMSB:0]   s6_pc;
   reg  [   31:0]   s6_insn;
   reg  [    1:0]   s6_priv;

   reg              s6_restart = 1;
   reg  [`XMSB:0]   s6_restart_pc;

   reg  [    4:0]   s6_rd = 0;  // != 0 => WE. !valid => 0
   reg  [`XMSB:0]   s6_wb_val;
   reg  [`XMSB:0]   s6_rs1, s6_rs2;

   /* Updates to CSR state */
   reg  [`XMSB:0]   s6_csr_mcause;
   reg  [`XMSB:0]   s6_csr_mepc;
   reg  [`XMSB:0]   s6_csr_mstatus;
   reg  [`XMSB:0]   s6_csr_mtval;

   reg  [`XMSB:0]   s6_csr_sepc;
   reg  [`XMSB:0]   s6_csr_scause;
   reg  [`XMSB:0]   s6_csr_stval;
// reg  [`XMSB:0]   s6_csr_stvec;

   reg  [   11:0]   s6_csr_mideleg;
   reg  [   11:0]   s6_csr_medeleg;
   reg              s6_branch_taken;
   reg              s6_csr_we;
   reg [`XMSB:0]    s6_csr_val;
   reg [`XMSB:0]    s6_csr_d;

   reg              s6_trap;
   reg [    3:0]    s6_trap_cause;
   reg [`XMSB:0]    s6_trap_val;
   reg              s6_intr;
   reg [    3:0]    s6_cause;
   reg              s6_deleg;
   reg [`XMSB:0]    s6_addr;

   wire [`XMSB:0]   m1_load_addr;

   wire [1:0] yags_new_direction =
              s5_yags_hit
              ? (s5_branch_taken
                 ? s5_yags_dir == `BTB_TYPE_BR_S_T ? `BTB_TYPE_BR_S_T : s5_yags_dir + 1
                 : s5_yags_dir == `BTB_TYPE_BR_S_N ? `BTB_TYPE_BR_S_N : s5_yags_dir - 1)
              : s5_branch_taken ? `BTB_TYPE_BR_W_T : `BTB_TYPE_BR_W_N;

   // A precise retirement RAS and branch history
   reg [`VMSB          :0] rras0 = 0, rras1 = 0, rras2 = 0;
   reg [`YAGS_INDEX_MSB:0] rbr_history = 0;
   always @(posedge clock) begin
      s6_valid_r      <= s5_valid;
      s6_pc           <= s5_pc;
      s6_insn         <= s5_insn;
      s6_rs1          <= s5_rs1;
      s6_rs2          <= s5_rs2;
      s6_rd           <= s5_valid ? s5_rd : 0;
      s6_branch_taken <= s5_branch_taken;
      s6_intr         <= csr_mip_and_mie != 0 && csr_mstatus`MIE;

      s6_wb_val       <= s5_wb_val;
      s6_flush        <= 0;
      s6_csr_val      <= s5_csr_val;
      s6_addr         <= s5_opcode == `LOAD || s5_opcode == `STORE ?
                         s5_rs1 + (s5_opcode == `LOAD ? s5_i_imm : s5_s_imm) : 0;

      s6_restart      <= s5_pc_insn_miss & s5_valid;
      s6_restart_pc   <= s5_insn_target;
      btb_update      <= s5_pc_insn_miss & s5_valid;
      btb_update_idx  <= s5_pc[`BTB_INDEX_MSB+2:2];
      btb_update_type <= `BTB_TYPE_BR_W_N;
      yags_update     <= 0;

      if (s5_valid)
        case (s5_opcode)
          `LOAD: begin
             // XXX This is conservative, but I just want it passing for now
             // XXX Could be retimed by precomputing s6_addr - s5_s_imm and then just compare with s5_rs1
             if (s6_valid && s6_insn`opcode == `STORE && s6_addr[`PMSB:2] == m1_load_addr[`PMSB:2] ||
                 s7_valid && s7_insn`opcode == `STORE && s7_addr[`PMSB:2] == m1_load_addr[`PMSB:2]) begin
                s6_flush <= 1;
                s6_restart <= 1;
                s6_restart_pc <= s5_pc;
`ifndef QUIET
                $display("RESTART: %x  load-hit-store", s5_pc);
`endif
             end
          end

          `BRANCH: begin
             rbr_history <= (rbr_history << 1) | s5_branch_taken;
             if (s5_branch_taken)
               if (s5_br_target_miss) begin
                  s6_restart <= 1;
                  s6_restart_pc <= s5_br_target;
               end else begin
                  btb_update <= 0; // The common path will presume a misprediction
                  s6_restart <= 0; // The common path will presume a misprediction
               end

             btb_update_tag <= s5_pc[`BTB_TAG_MSB+`BTB_INDEX_MSB+3:`BTB_INDEX_MSB+3];
             btb_update_target <= s5_br_target >> 2;

`ifndef QUIET
             if (s5_yags_hit)
               $display("%x/%x hit in YAGS[%x] with direction %d, updating to %d", s5_pc, rbr_history,
                        s5_pc[`YAGS_INDEX_MSB+2:2] ^ rbr_history,
                        s5_yags_dir, yags_new_direction);
             else
               $display("%x/%x updating YAGS[%x] to direction %d", s5_pc, rbr_history,
                        s5_pc[`YAGS_INDEX_MSB+2:2] ^ rbr_history,
                        yags_new_direction);
`endif
             yags_update <= 1;
             yags_update_idx <= s5_yags_idx;
             yags_update_tag <= s5_pc[`YAGS_TAG_MSB+`YAGS_INDEX_MSB+3:`YAGS_INDEX_MSB+3];
             yags_update_direction <= yags_new_direction;

             if (!(s5_btb_hit && s5_yags_hit)) begin
                if (s5_branch_taken && (s5_btb_type != `BTB_TYPE_BR_S_T || !s5_btb_hit)) begin
                   btb_update <= 1;
                   btb_update_type <= s5_btb_type <= `BTB_TYPE_BR_S_T && s5_btb_hit ? s5_btb_type + 1 : `BTB_TYPE_BR_W_T;
                end

                if (!s5_branch_taken && (s5_btb_type != `BTB_TYPE_BR_S_N || !s5_btb_hit)) begin
                   btb_update <= 1;
                   btb_update_type <= s5_btb_type <= `BTB_TYPE_BR_S_T && s5_btb_hit ? s5_btb_type - 1 : `BTB_TYPE_BR_W_N;
                end
             end

`ifndef QUIET
             if (s5_branch_taken ? s5_br_target_miss : s5_pc_insn_miss)
               $display("RESTART: %x %1s BRANCH mispredicted as %x should be %x",
                        s5_pc,
                        s5_branch_taken ? "TAKEN" : "NOT-taken",
                        s5_npc,
                        s5_branch_taken ? s5_br_target : s5_pc + 4);
             else if (s5_branch_taken) // Correctly predicted non-taken branches are boring
               $display("WINNER_: %x %1s BRANCH predicted correctly!",
                        s5_pc, s5_branch_taken ? "TAKEN" : "NOT-taken");
`endif
          end

          `JALR: begin
             if (s5_jalr_target_miss) begin
                s6_restart <= 1;
                s6_restart_pc <= s5_jalr_target;
                btb_update <= 1;
                btb_update_tag <= s5_pc[`BTB_TAG_MSB+`BTB_INDEX_MSB+3:`BTB_INDEX_MSB+3];
                // rd           |  rs1          | rs1=rd        | Interpretation
                // !r1/r5       | !r1/r5        | -             | indirect branch
                // !r1/r5       |  r1/r5        | -             | return
                // r1/r5        | !r1/r5        | -             | call
                // r1/r5        | r1/r5         | rs1!=rd       | call
                // r1/r5        | r1/r5         | rs1=rd        | Co-jump (XXX not handled)

                // XXX do in decode
                case ({s5_insn`rd == 1 || s5_insn`rd == 5,s5_insn`rs1 == 1 || s5_insn`rs1 == 5})
                  0: btb_update_type <= `BTB_TYPE_JUMP;
                  1: btb_update_type <= `BTB_TYPE_RETURN;
                  2, 3: btb_update_type <= `BTB_TYPE_CALL;
                endcase
                btb_update_target <= s5_jalr_target >> 2;
`ifndef QUIET
                $display("RESTART: %x JALR mispredicted as %x instead of %x", s5_pc, s5_npc, s5_jalr_target);
`endif
             end else begin
`ifndef QUIET
                $display("WINNER_: %x JALR predicted correctly!", s5_pc);
`endif
                btb_update <= 0; // The common path will presume a misprediction
                s6_restart <= 0; // The common path will presume a misprediction
             end

             case ({s5_insn`rd == 1 || s5_insn`rd == 5,s5_insn`rs1 == 1 || s5_insn`rs1 == 5})
               1: begin
                  rras0 <= rras1;
                  rras1 <= rras2;
                  // keep ras2
                  rras2 <= 0; // XXX just to make debugging easier
`ifndef QUIET
                $display("         RRAS %x %x %x", rras1, rras2, 0);
`endif
               end
               2, 3: begin
                  // Old ras2 lost
                  rras2 <= rras1;
                  rras1 <= rras0;
                  rras0 <= s5_pc + 4;
`ifndef QUIET
                $display("         RRAS %x %x %x", s5_pc + 4, rras0, rras1);
`endif
               end
             endcase
          end

          `JAL: begin
             if (s5_pc_insn_miss) begin
                s6_restart <= 1;
                s6_restart_pc <= s5_insn_target;

                btb_update <= 1;
                btb_update_tag <= s5_pc[`BTB_TAG_MSB+`BTB_INDEX_MSB+3:`BTB_INDEX_MSB+3];
                // rd           | Interpretation
                // !r1/r5       | jump
                // r1/r5        | call

                // XXX do in decode
                case ({s5_insn`rd == 1 || s5_insn`rd == 5})
                  0: btb_update_type <= `BTB_TYPE_JUMP;
                  1: btb_update_type <= `BTB_TYPE_CALL;
                endcase
                btb_update_target <= s5_insn_target >> 2;
`ifndef QUIET
                $display("RESTART: %x JAL mispredicted as %x instead of %x", s5_pc, s5_npc, s5_insn_target);
             end else begin
                $display("WINNER_: %x JAL predicted correctly!", s5_pc);
`endif
             end

             // Update RRAS
             case ({s5_insn`rd == 1 || s5_insn`rd == 5})
               1: begin
                  // Old ras2 lost
                  rras2 <= rras1;
                  rras1 <= rras0;
                  rras0 <= s5_pc + 4;
               end
             endcase
          end

          `SYSTEM: begin
             s6_restart <= 1;
             case (s5_insn`funct3)
               `PRIV:
                 case (s5_insn`imm11_0)
                   `ECALL, `EBREAK: begin
                      s6_restart_pc <= csr_mtvec;
`ifndef QUIET
                      $display("RESTART: %x ECALL or EBREAK", s5_pc);
`endif
                   end
                   `MRET: begin
                      s6_restart_pc <= csr_mepc;
`ifndef QUIET
                      $display("RESTART: %x MRET", s5_pc);
`endif
                   end
                 endcase
               default: begin
`ifndef QUIET
                 $display("RESTART: %x other SYSTEM", s5_pc);
`endif
               end
             endcase
          end

          `MISC_MEM:
            case (s5_insn`funct3)
              `FENCE_I:
                begin
                   s6_restart <= 1;
`ifndef QUIET
                   $display("RESTART: %x FENCE_I", s5_pc);
`endif
                end
            endcase
        endcase;

      /*
       * XXX This is awkward; with the exception below, everything for
       * s5 restart depends on s4.  However we do this to get more
       * time to determine the exceptions and we do want restarts as
       * early as possible otherwise.  Thus, s6_trap must also be
       * considered as having invalidated s5 for the next stage.
       */
      if (s6_trap || s6_intr) begin
`ifndef QUIET
         if (s6_trap_cause)
           $display("%5d  %x %x EXCEPTION %d", $time/10,
                    s6_pc, s6_insn, s6_trap_cause);
`endif
         s6_flush <= 1;
         s6_restart <= 1;
         s6_restart_pc <= csr_mtvec;
      end

      if (reset) begin
         s6_restart <= 1;
         s6_restart_pc <= `INIT_PC;
`ifndef QUIET
         $display("RESTART: reset");
`endif
      end
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
      s6_csr_we                         = 0;
      s6_priv                           = priv;
      s6_csr_mcause                     = csr_mcause;
      s6_csr_mepc                       = csr_mepc;
      s6_csr_mstatus                    = csr_mstatus;
      s6_csr_mtval                      = csr_mtval;

      s6_csr_scause                     = csr_scause;
      s6_csr_sepc                       = csr_sepc;
      s6_csr_stval                      = csr_stval;

      s6_csr_mideleg                    = csr_mideleg;
      s6_csr_medeleg                    = csr_medeleg;

      s6_trap                           = 0;
      s6_trap_cause                     = 0;
      s6_trap_val                       = 0;
      s6_csr_d                          = 'h X;
      s6_cause                          = 0;
      s6_deleg                          = 0;

      case (s6_insn`opcode)
        `OP_IMM, `OP, `AUIPC, `LUI: ;

        // XXX Should compute ctl targets at end of decode and use that for misaligned fetch tests
        `BRANCH:
           if (s6_restart_pc[1] && s6_branch_taken) begin
              s6_trap                   = s6_valid;
              s6_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              s6_trap_val               = s6_restart_pc;
           end

        `JALR: begin
           if (s6_restart_pc[1]) begin
              s6_trap                   = s6_valid;
              s6_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              s6_trap_val               = s6_restart_pc;
           end
        end

        `JAL: begin
           if (s6_restart_pc[1]) begin
              s6_trap                   = s6_valid;
              s6_trap_cause             = `CAUSE_MISALIGNED_FETCH;
              s6_trap_val               = s6_restart_pc;
           end
        end

        // XXX Do we _need_ to write CSR in s6?  Don't we have enough time to delay it a stage
        `SYSTEM: begin
           s6_csr_we                    = s6_valid;
           case (s6_insn`funct3)
             `CSRRS:  begin s6_csr_d    = s6_csr_val |  s6_rs1; if (s6_insn`rs1 == 0) s6_csr_we = 0; end
             `CSRRC:  begin s6_csr_d    = s6_csr_val &~ s6_rs1; if (s6_insn`rs1 == 0) s6_csr_we = 0; end
             `CSRRW:  begin s6_csr_d    =               s6_rs1; end
             `CSRRSI: begin s6_csr_d    = s6_csr_val |  {27'd0, s6_insn`rs1}; end
             `CSRRCI: begin s6_csr_d    = s6_csr_val &~ {27'd0, s6_insn`rs1}; end
             `CSRRWI: begin s6_csr_d    = {{(`XMSB-4){1'd0}}, s6_insn`rs1}; end
             `PRIV: begin
                s6_csr_we               = 0;
                case (s6_insn`imm11_0)
                  `ECALL, `EBREAK: begin
                     s6_trap            = s6_valid;
                     s6_trap_cause      = s6_insn`imm11_0 == `ECALL
                                          ? `CAUSE_USER_ECALL | {2'd0,priv}
                                          : `CAUSE_BREAKPOINT;
                  end

                  `MRET: if (s6_valid) begin
                     s6_csr_mstatus`MIE = csr_mstatus`MPIE;
                     s6_csr_mstatus`MPIE= 1;
                     s6_priv            = csr_mstatus`MPP;
                     s6_csr_mstatus`MPP = `PRV_U;
                  end

                  `WFI: ; // XXX Should restart and block fetch until interrupt becomes pending

                  default: begin
                     s6_trap            = s6_valid;
                     s6_trap_cause      = `CAUSE_ILLEGAL_INSTRUCTION;
                  end
                endcase
             end
           endcase

           // Trap illegal CSRs accesses (ie. CSRs without permissions)
           case (s6_insn`funct3)
             `CSRRS, `CSRRC, `CSRRW, `CSRRSI, `CSRRCI, `CSRRWI:
               if (((s6_insn`imm11_0 & 12'hC00) == 12'hC00) && s6_csr_we || priv < s6_insn[31:30]) begin
                  s6_trap               = s6_valid;
                  s6_trap_cause         = `CAUSE_ILLEGAL_INSTRUCTION;
               end
           endcase
        end

        `MISC_MEM:
            case (s6_insn`funct3)
              `FENCE, `FENCE_I: ;
              default: begin
                 s6_trap                = s6_valid;
                 s6_trap_cause          = `CAUSE_ILLEGAL_INSTRUCTION;
              end
          endcase

        `LOAD: begin
           if (s6_insn == 0) begin
                s6_trap                 = s6_valid;
                s6_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
           end
           case (s6_insn`funct3)
             3, 6, 7: begin
                s6_trap                 = s6_valid;
                s6_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
             end
             default: begin
                s6_trap                 = s6_valid & s6_misaligned;
                s6_trap_cause           = `CAUSE_MISALIGNED_LOAD;
                s6_trap_val             = s6_addr;
             end
           endcase
        end

        `STORE: begin
           //store_addr              = s6_rs1 + s6_s_imm;
           case (s6_insn`funct3)
             3, 4, 5, 6, 7: begin
                s6_trap                 = s6_valid;
                s6_trap_cause           = `CAUSE_ILLEGAL_INSTRUCTION;
             end
             default: begin
                s6_trap                 = s6_valid & s6_misaligned;
                s6_trap_cause           = `CAUSE_MISALIGNED_STORE;
                s6_trap_val             = s6_addr;
             end
           endcase
        end

        default: begin
           s6_trap                      = s6_valid;
           s6_trap_cause                = `CAUSE_ILLEGAL_INSTRUCTION;
        end
      endcase

      if (s6_trap || s6_intr) begin
         if (s6_intr) begin
            // Awkward priority scheme
            s6_cause                    = (csr_mip_and_mie[1] ? 1 :
                                           csr_mip_and_mie[3] ? 3 :
                                           csr_mip_and_mie[5] ? 5 :
                                           csr_mip_and_mie[7] ? 7 :
                                           csr_mip_and_mie[9] ? 9 :
                                           11);
            s6_trap_val                 = 0;
         end else
            s6_cause                    = s6_trap_cause;

         s6_deleg = priv <= 1 && ((s6_intr ? csr_mideleg : csr_medeleg) >> s6_cause) & 1'd1;

         if (s6_deleg) begin
            s6_csr_scause[`XMSB]        = s6_intr;
            s6_csr_scause[`XMSB-1:0]    = {{(`XMSB-4){1'd0}},s6_cause};
            s6_csr_sepc                 = s6_pc;
            s6_csr_stval                = s6_trap_val;
            s6_csr_mstatus`SPIE         = csr_mstatus`SIE;
            s6_csr_mstatus`SIE          = 0;
            s6_csr_mstatus`SPP          = priv[0]; // XXX SPP is one bit whose two values are USER and SUPERVISOR?
            s6_priv                     = `PRV_S;
         end else begin
            s6_csr_mcause[`XMSB]        = s6_intr;
            s6_csr_mcause[`XMSB-1:0]    = {{(`XMSB-4){1'd0}}, s6_cause};
            s6_csr_mepc                 = s6_pc;
            s6_csr_mtval                = s6_trap_val;
            s6_csr_mstatus`MPIE         = csr_mstatus`MIE;
            s6_csr_mstatus`MIE          = 0;
            s6_csr_mstatus`MPP          = priv;
            s6_priv                     = `PRV_M;
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
      csr_mip[7]                        <= s7_timer_interrupt;

      priv                              <= s6_priv;
      csr_mcause                        <= s6_csr_mcause;
      csr_mepc                          <= s6_csr_mepc;
      csr_mstatus                       <= s6_csr_mstatus;
      csr_mtval                         <= s6_csr_mtval;
      csr_scause                        <= s6_csr_scause;
      csr_sepc                          <= s6_csr_sepc;
      csr_stval                         <= s6_csr_stval;

      csr_mideleg                       <= s6_csr_mideleg;
      csr_medeleg                       <= s6_csr_medeleg;
      csr_minstret                      <= csr_minstret + s7_valid;

      /* CSR write port (notice, this happens in EX) */
      if (s6_csr_we) begin
         case (s6_insn`imm11_0)
           `CSR_FCSR:      {csr_frm,csr_fflags} <= s6_csr_d[7:0];
           `CSR_FFLAGS:    csr_fflags   <= s6_csr_d[4:0];
           `CSR_FRM:       csr_frm      <= s6_csr_d[2:0];
           `CSR_MCAUSE:    csr_mcause   <= s6_csr_d;
//         `CSR_MCYCLE:    csr_mcycle   <= s6_csr_d;
           `CSR_MEPC:      csr_mepc     <= s6_csr_d & ~3;
           `CSR_MIE:       csr_mie      <= s6_csr_d[11:0];
//         `CSR_MINSTRET:  csr_minstret <= s6_csr_d;
           `CSR_MIP:       csr_mip      <= s6_csr_d & `CSR_MIP_WMASK | csr_mip & ~`CSR_MIP_WMASK;
           `CSR_MIDELEG:   csr_mideleg  <= s6_csr_d[11:0];
           `CSR_MEDELEG:   csr_medeleg  <= s6_csr_d[11:0];
           `CSR_MSCRATCH:  csr_mscratch <= s6_csr_d;
           `CSR_MSTATUS:   csr_mstatus  <= s6_csr_d & ~(15 << 13); // No FP or XS;
           `CSR_MTVEC:     csr_mtvec    <= s6_csr_d & ~1; // We don't support vectored interrupts
           `CSR_MTVAL:     csr_mtvec    <= s6_csr_d;

           `CSR_SCAUSE:    csr_scause   <= s6_csr_d;
           `CSR_SEPC:      csr_sepc     <= s6_csr_d;
           `CSR_STVEC:     csr_stvec    <= s6_csr_d & ~1; // We don't support vectored interrupts
           `CSR_STVAL:     csr_stvec    <= s6_csr_d;

           `CSR_PMPCFG0: ;
           `CSR_PMPADDR0: ;
`ifndef QUIET
           default:
             $display("                                            warning: unimplemented csr%x",
                      s6_insn`imm11_0);
`endif
         endcase
`ifndef QUIET
         $display("                                            csr%x <- %x",
                  s6_insn`imm11_0, s6_csr_d);
`endif
      end
   end




   reg s6_misaligned;
   always @(*)
     case (s6_insn`funct3 & 3)
       0: s6_misaligned =  0;            // Byte
       1: s6_misaligned =  s6_addr[  0]; // Half
       2: s6_misaligned = |s6_addr[1:0]; // Word
       3: s6_misaligned =  1'hX;
     endcase

   /* Load path */

   /* Store path */

   wire [`XMSB:0] s6_st_data;
   wire [    3:0] s6_st_mask;

   yarvi_st_align yarvi_st_align1
     (s6_insn`funct3, s6_addr[1:0], s6_rs2, s6_st_mask, s6_st_data);

   wire             s6_addr_in_mem = (s6_addr & (-1 << (`PMSB+1))) == 32'h80000000;
   wire [`PMSB-2:0] s6_wi = s6_addr[`PMSB:2];
   wire             s6_we = (s6_valid &&
                             !s6_flush &&
                             !s6_trap &&
                             !s6_intr &&
                             s6_insn`opcode == `STORE &&
                             s6_addr_in_mem);



   // S7 - Write back committed results, store to memory
   reg              s7_valid = 0;
   reg  [`XMSB:0]   s7_wb_val;
   reg  [`PMSB:2]   s7_addr;
   reg              s7_timer_interrupt_future;
   reg  [`VMSB:0]   s7_pc;
   reg  [   31:0]   s7_insn;
   reg  [    4:0]   s7_rd = 0;
   reg              s7_timer_interrupt;
   reg  [   63:0]   mtime_future;
   always @(posedge clock) begin
      s7_valid          <= s6_valid & !s6_flush && !s6_trap && !s6_intr;
      s7_pc             <= s6_pc;
      s7_insn           <= s6_insn;
      s7_rd             <= s6_valid ? s6_rd : 0;
      s7_addr[`PMSB:2]  <= s6_addr[`PMSB:2];
      s7_wb_val         <= s6_wb_val;
      if (|s7_rd & s7_valid) begin
         regs[s7_rd]    <= m3_wb_val;
         //$display("%x %x r%1d %x", priv, s7_pc, s7_rd, m3_wb_val);
      end

      /* Memory mapped io devices (only word-wide accesses are allowed) */
      mtime_future                      <= mtime_future + 1; // XXX Yes, this is terrible
      s7_timer_interrupt_future         <= mtime > mtimecmp;
      mtime                             <= mtime_future;
      s7_timer_interrupt                <= s7_timer_interrupt_future;

      if (s6_valid && s6_insn`opcode == `STORE && (s6_addr & 32'h4FFFFFF3) == 32'h40000000)
        case (s6_addr[3:2])
          0: mtime[31:0]                <= s6_rs2;
          1: mtime[63:32]               <= s6_rs2;
          2: mtimecmp[31:0]             <= s6_rs2;
          3: mtimecmp[63:32]            <= s6_rs2;
        endcase

      if (s6_we & s6_st_mask[0]) data0[s6_wi] <= s6_st_data[ 7: 0];
      if (s6_we & s6_st_mask[1]) data1[s6_wi] <= s6_st_data[15: 8];
      if (s6_we & s6_st_mask[2]) data2[s6_wi] <= s6_st_data[23:16];
      if (s6_we & s6_st_mask[3]) data3[s6_wi] <= s6_st_data[31:24];
      if (s6_we & s6_st_mask[0]) code0[s6_wi] <= s6_st_data[ 7: 0];
      if (s6_we & s6_st_mask[1]) code1[s6_wi] <= s6_st_data[15: 8];
      if (s6_we & s6_st_mask[2]) code2[s6_wi] <= s6_st_data[23:16];
      if (s6_we & s6_st_mask[3]) code3[s6_wi] <= s6_st_data[31:24];

      if (reset) begin
         mtime_future                      <= 0;
         mtimecmp                          <= 0;
      end
   end


`ifdef BEGIN_SIGNATURE
   reg  [`VMSB  :0] dump_addr;
`endif
   always @(posedge clock)
     if (!restart && s6_valid && s6_insn`opcode == `STORE && !s6_misaligned) begin
`ifndef QUIET
        if (!s6_addr_in_mem)
          $display("store %x -> [%x]/%x", s6_st_data, s6_addr, s6_st_mask);
`endif

`ifdef TOHOST
        if (s6_st_mask == 15 & s6_addr == 'h`TOHOST) begin
`ifndef QUIET
           $display("TOHOST = %d", s6_st_data);
`else
           $write("%c", s6_st_data[7:0]);
`endif


`ifdef BEGIN_SIGNATURE
           $display("");
           $display("Signature Begin");
           for (dump_addr = 'h`BEGIN_SIGNATURE; dump_addr < 'h`END_SIGNATURE; dump_addr=dump_addr+4)
              $display("%x", {data3[dump_addr[`PMSB:2]],data2[dump_addr[`PMSB:2]],data1[dump_addr[`PMSB:2]],data0[dump_addr[`PMSB:2]]});
`endif
`ifndef KEEP_GOING
           $finish;
`endif
        end
`endif
     end



   // S8 - hold register file result for forwarding
   // XXX the retire_XXX / debug registers should just taken from s6.
   reg  [`XMSB:0]   s8_wb_val;
   always @(posedge clock) begin
      s8_wb_val     <= m3_wb_val;

      retire_valid  <= s7_valid;
      retire_priv   <= priv;
      retire_pc     <= s7_pc;
      retire_insn   <= s7_insn;
      retire_rd     <= s7_rd;
      retire_wb_val <= m3_wb_val;
      debug         <= retire_wb_val;
   end




   // Memory pipeline - S5 - S7
   assign         m1_load_addr = s5_rs1 + s5_i_imm; // Need full address
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
      m2_memory_data    <= {data3[m1_load_addr[`PMSB:2]],data2[m1_load_addr[`PMSB:2]],data1[m1_load_addr[`PMSB:2]],data0[m1_load_addr[`PMSB:2]]};
      m3_insn           <= s6_insn;
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
     (m3_insn`opcode != `LOAD, s7_wb_val, // XXX Drop the s7_wb_val -> m3_wb_val bypass?
      m3_insn`funct3, m3_load_addr[1:0],
      m3_load_addr_in_mem ? m3_memory_data : m3_mmio_data,
      m3_wb_val);




   // Module outputs
   assign           restart    = s6_restart;
   assign           restart_pc = s6_restart_pc;

`ifdef __ICARUS__
`define HAS_PLUSARGS 1
`endif

`ifdef VERILATOR
`define HAS_PLUSARGS 1
`endif

`ifdef YOSYS
// Doesn't appear to support $value$plusargs
`endif

`ifdef ALTERA_RESERVED_QIS
// Doesn't appear to support $value$plusargs
`endif

`ifdef HAS_PLUSARGS
   reg [511:0]   init_mem_0 = "init_mem.0.hex",
                 init_mem_1 = "init_mem.1.hex",
                 init_mem_2 = "init_mem.2.hex",
                 init_mem_3 = "init_mem.3.hex";
`endif

   reg [31:0] i;
   initial begin
`ifndef QUIET
      $display("Initializing the %d B data memory", 1 << (`PMSB + 1));
`endif
`ifdef HAS_PLUSARGS
      if ($value$plusargs("INIT0=%s", init_mem_0))
         /*$display("Loading lane 0 from %s", init_mem_0)*/;
      if ($value$plusargs("INIT1=%s", init_mem_1))
         /*$display("Loading lane 1 from %s", init_mem_1)*/;
      if ($value$plusargs("INIT2=%s", init_mem_2))
         /*$display("Loading lane 2 from %s", init_mem_2)*/;
      if ($value$plusargs("INIT3=%s", init_mem_3))
         /*$display("Loading lane 3 from %s", init_mem_3)*/;
      $readmemh(init_mem_0, code0);
      $readmemh(init_mem_0, data0);
      $readmemh(init_mem_1, code1);
      $readmemh(init_mem_1, data1);
      $readmemh(init_mem_2, code2);
      $readmemh(init_mem_2, data2);
      $readmemh(init_mem_3, code3);
      $readmemh(init_mem_3, data3);
`else
      $readmemh("init_mem.0.hex", code0);
      $readmemh("init_mem.0.hex", data0);
      $readmemh("init_mem.1.hex", code1);
      $readmemh("init_mem.1.hex", data1);
      $readmemh("init_mem.2.hex", code2);
      $readmemh("init_mem.2.hex", data2);
      $readmemh("init_mem.3.hex", code3);
      $readmemh("init_mem.3.hex", data3);
`endif

      for (i = 0; i < 32; i = i + 1)
        regs[i[4:0]] = {26'd0,i[5:0]};
      regs[2] = 'h80000000 + (1 << (`PMSB + 1)); // XXX Total hack
      for (i = 0; i < 2 << `BTB_INDEX_MSB; i = i + 1) begin
         btb_target[i] = 0;
         btb_type[i] = 0;
         btb_tag[i] = ~0;
      end
      for (i = 0; i < 2 << `YAGS_INDEX_MSB; i = i + 1) begin
         yags_tag[i] = ~0;
         yags_direction[i] = 1;
      end
   end

`ifdef DISASSEMBLE
   yarvi_disass disass
     ( .clock  (clock)
     , .info   ({restart, 1'b1, s3_valid, s4_valid, s5_valid, s6_valid, s7_valid})
     , .valid  (s7_valid)
     , .prv    (priv)
     , .pc     (s7_pc)
     , .insn   (s7_insn)
     , .wb_rd  (s7_rd)
     , .wb_val (m3_wb_val));
`endif
endmodule
