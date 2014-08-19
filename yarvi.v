// -----------------------------------------------------------------------
//
//   Copyright 2014 Tommy Thorn - All Rights Reserved
//
//   This program is free software; you can redistribute it and/or modify
//   it under the terms of the GNU General Public License as published by
//   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
//   Bostom MA 02111-1307, USA; either version 2 of the License, or
//   (at your option) any later version; incorporated herein by reference.
//
// -----------------------------------------------------------------------

/*************************************************************************

This is an attempt at making a nearly as simple as possible implementation
of RISC-V RV32I.  The present subset is a simple one-hot state machine.
The desire to use block ram for memories *and* register file dictates the
need for at least three stages:

                        Unpipelined State Machine
                              IF -> DE -> EX
                               ^----------/

This guarantees a CPI of 3 as no hazards can occur (we don't currently
deal with memory waits).  Since branches only depend on registers, we can
trivially lower this to 2 cycles by issuing branches from DE and thus
overlap EX with IF for the next instruction (a fairly standard trick):

                    Partically Pipelined State Machine

                              IF -> DE -> EX
                               ^----/

There are two obvious directions from here:

1) Have two hardware threads interleave the pipeline, getting 100%
   utilization.

2) Overlap IF/EX with DE.  This requires solving two problems:

   a) Back-to-back dependencies will require forwarding the result
      from EX to DE.

      Adds to the critical path through EX

   b) We have to assume or "predict" the outcome of branches and
      compensate for mistakes.

      The compensation implies interlocks (stalling) and/or
      restarts/flushes.  All of this is likely to add to a critical path.



 Below we focus on the Unpipelined State Machine

 CONVENTION:
   var = array[r], where r is a [subfield of] a register assigned with <=
   r <= y, only if y is a [subfield of] a name (register or wire)
   All memory reads must be in the form:

                                   wire q = mem[y];

   Names reflect the stage/state from which they are outputs, eg. if_inst
   is the instruction fetched in IF, de_rs1_val the value of rs1 fetched
   by DE, etc.

 Conceptually: (where <= is a synchronous assignment and = an alias)

   if_pc <= if_pc + 4
   if_inst = code[if_pc]

   de_pc <= if_pc
   de_inst <= if_inst
   de_rs1_val = regs[de_inst`rs1]
   de_rs2_val = regs[de_inst`rs2]
   ex_load_addr = de_rs1_val + de_inst`off

   ex_pc <= de_pc
   ex_inst <= de_inst
   ex_rs1_val <= de_rs1_val
   ex_rs2_val <= de_rs2_val
   ex_load_addr <= de_load_addr

   ex_res = ex_inst`opcode == ADD ? ex_rs1_val + ex_rs2_val
                                  : ex_rs1_val - ex_rs2_val

   ex_loaded = memory[ex_load_addr]

   regs[ex_inst`rd] <= ex_inst`opcode == LOAD ? ex_loaded : ex_res


   With bypass:

      de_rs1_val = de_inst`rs1 == ex_inst`rd ? ex_res : regs[de_inst`rs1]
      de_rs2_val = de_inst`rs2 == ex_inst`rd ? ex_res : regs[de_inst`rs2]

*************************************************************************/


`timescale 1ns/10ps

`include "riscv.h"

`define MEMWORDS_LG2 15 // 128 KiB
`define MEMWORDS (1 << `MEMWORDS_LG2)
`define INIT_PC 'h1000_0054
`define DATA_START 32'h1000_0000

module yarvi( input  wire        clk
            , input  wire        reset

            , output reg  [29:0] address
            , output reg         writeenable = 0
            , output reg  [31:0] writedata
            , output reg  [ 3:0] byteena
            , output reg         readenable = 0
            , input  wire [31:0] readdata
            );

   /* Global state */

   reg  [31:0] code_mem [0:255];
   reg  [ 7:0] mem0[`MEMWORDS-1:0];
   reg  [ 7:0] mem1[`MEMWORDS-1:0];
   reg  [ 7:0] mem2[`MEMWORDS-1:0];
   reg  [ 7:0] mem3[`MEMWORDS-1:0];


   /* CPU state.  These are a special-case of pipeline registers.  As
      they are only (and must only be) written by the EX stage, we
      needn't keeps per-stage versions of these.

      Note, a pipelined implementation will necessarily have access to
      the up-to-date version of the state, thus care must be taken to
      forward the correct valid where possible and restart whenever
      the use of an out-of-date value is detected.  In the cases where
      the update is rare it's likely better to unconditionally restart
      the pipeline whenever the update occurs (eg. writes of
      csr_ptbr).

      Exceptions to this are CSR count, cycle, and, time which are
      generally updated independent of what happens in the
      pipeline. */

   reg  [31:0] regs[0:31];

   reg  [ 7:0] csr_fcsr         = 0;
   reg  [31:0] csr_sup0         = 0;
   reg  [31:0] csr_sup1         = 0;
   reg  [31:0] csr_epc;         // NB: csr_epc[1:0] === 0
   reg  [31:0] csr_badvaddr     = 0;
   reg  [31:0] csr_ptbr         = 0;
   reg  [31:0] csr_count        = 0;
   reg  [31:0] csr_compare      = 0;
   reg  [31:0] csr_evec         = 'h 2000;
   reg  [31:0] csr_cause        = 0;
   reg  [31:0] csr_status       = 'h 1;  /* S */
   reg  [31:0] csr_tohost       = 0;
   reg  [31:0] csr_fromhost     = 0;

   reg  [63:0] csr_cycle        = 0;
   reg  [63:0] csr_time         = 0;
   reg  [63:0] csr_instret      = 0;

   // XXX experimental
   reg  [31:0] csr_storeaddr;

   wire interrupt = (csr_status`IM & csr_status`IP) != 0 && csr_status`EI;
   reg [2:0] interrupt_cause;
   always @(*)
       case (csr_status`IM & csr_status`IP)
       'bxxxxxxx1: interrupt_cause = 0;
       'bxxxxxx10: interrupt_cause = 1;
       'bxxxxx100: interrupt_cause = 2;
       'bxxxx1000: interrupt_cause = 3;
       'bxxx10000: interrupt_cause = 4;
       'bxx100000: interrupt_cause = 5;
       'bx1000000: interrupt_cause = 6;
       'b10000000: interrupt_cause = 7;
       'b00000000: interrupt_cause = 'h x;
       endcase

   /* Forwarded EX registers */
   reg         ex_valid = 0;
   reg  [31:0] ex_next_pc;

//// INSTRUCTION FETCH ////

   reg         if_valid;
   reg  [31:0] if_pc;

   always @(posedge clk) begin
      if_valid <= ex_valid | reset;
      if_pc    <= reset ? `INIT_PC : ex_next_pc;
   end

   wire [31:0] if_inst = code_mem[if_pc[9:2]];

//// DECODE AND REGISTER FETCH ////

   reg         de_valid;
   reg  [31:0] de_pc;
   reg  [31:0] de_inst;

   reg  [31:0] de_csr_val;

   always @(posedge clk) begin
      de_valid  <= if_valid & !reset;
      de_pc     <= if_pc;
      de_inst   <= if_inst;
   end

   wire [31:0] de_rs1_val      = regs[de_inst`rs1];
   wire [31:0] de_rs2_val      = regs[de_inst`rs2];

   wire [31:0] de_rs1_val_cmp  = (~de_inst`br_unsigned << 31) ^ de_rs1_val;
   wire [31:0] de_rs2_val_cmp  = (~de_inst`br_unsigned << 31) ^ de_rs2_val;
   wire        de_cmp_eq       = de_rs1_val     == de_rs2_val;
   wire        de_cmp_lt       = de_rs1_val_cmp  < de_rs2_val_cmp;
   wire        de_branch_taken = (de_inst`br_rela ? de_cmp_lt : de_cmp_eq) ^ de_inst`br_negate;

   wire        de_sign         = de_inst[31];
   wire [19:0] de_sign20       = {20{de_sign}};
   wire [11:0] de_sign12       = {12{de_sign}};

   // I-type
   wire [31:0] de_i_imm        = {de_sign20, de_inst`funct7, de_inst`rs2};

   // S-type
   wire [31:0] de_s_imm        = {de_sign20,           de_inst`funct7,      de_inst`rd};
// This doesn't work, at least Icarus generates strange results
// wire [31:0] de_sb_imm       = {de_sign20, de_inst`rd[0], de_inst`funct7[5:0], de_inst`rd[4:1], 1'd0};
   wire [31:0] de_sb_imm       = {de_sign20, de_inst[7], de_inst[30:25], de_inst`rd & 5'd30};

   // U-type
// wire [31:0] de_u_imm        = {de_sign12, de_inst`funct7, de_inst`rs2, de_inst`rs1, de_inst`funct3};
   wire [31:0] de_uj_imm       = {de_sign12, de_inst[19:12], de_inst[20], de_inst[30:21], 1'd0};

   wire [31:0] de_rs2_val_or_imm = de_inst`opcode == `OP_IMM ? de_i_imm : de_rs2_val;

   wire [31:0] de_load_addr    = de_rs1_val + de_i_imm;
   wire [31:0] de_store_addr   = de_rs1_val + de_s_imm;
   wire [`MEMWORDS_LG2-1:0]
               de_store_ea     = de_store_addr[`MEMWORDS_LG2+1:2];
   wire [ 3:0] de_bytemask     = de_inst`funct3 == 0 ? 4'd 1 : de_inst`funct3 == 1 ? 4'd 3 : 4'd 15;
   wire [ 3:0] de_byteena      = de_bytemask << de_store_addr[1:0];
   wire        de_store        = de_valid && de_inst`opcode == `STORE;
   wire        de_store_local  = de_store && de_store_addr[31:`MEMWORDS_LG2+2] == (`DATA_START >> (`MEMWORDS_LG2 + 2));
   wire [31:0] de_rs2_val_shl  = de_rs2_val << (de_store_addr[1:0]*8);

   reg [11:0] de_csrd;

   always @(*)
     case (de_inst`opcode)
     `CSRRS:  de_csrd = de_inst`rs1 ? de_inst`imm11_0 : 0;
     `CSRRC:  de_csrd = de_inst`imm11_0;
     `CSRRW:  de_csrd = de_inst`imm11_0;
     `CSRRSI: de_csrd = de_inst`imm11_0;
     `CSRRCI: de_csrd = de_inst`imm11_0;
     `CSRRWI: de_csrd = de_inst`imm11_0;
     default: de_csrd = 0;
     endcase

   always @(*)
     case (de_inst`imm11_0)
     `CSR_FFLAGS:       de_csr_val = csr_fcsr[4:0];
     `CSR_FRM:          de_csr_val = csr_fcsr[7:5];
     `CSR_FCSR:         de_csr_val = csr_fcsr;

     `CSR_SUP0:         de_csr_val = csr_sup0;
     `CSR_SUP1:         de_csr_val = csr_sup1;
     `CSR_EPC:          de_csr_val = csr_epc;
     `CSR_BADVADDR:     de_csr_val = csr_badvaddr;
     `CSR_PTBR:         de_csr_val = csr_ptbr;
     `CSR_ASID:         de_csr_val = 0;
     `CSR_COUNT:        de_csr_val = csr_count;
     `CSR_COMPARE:      de_csr_val = csr_compare;
     `CSR_EVEC:         de_csr_val = csr_evec;
     `CSR_CAUSE:        de_csr_val = csr_cause;
     `CSR_STATUS:       de_csr_val = csr_status;
     `CSR_HARTID:       de_csr_val = 0;
     `CSR_IMPL:         de_csr_val = 0;
     `CSR_FATC:         de_csr_val = 0; // XXX illegal, trap
     `CSR_SEND_IPI:     de_csr_val = 0; // XXX illegal, trap
     `CSR_CLEAR_IPI:    de_csr_val = 0; // XXX illegal, trap
     `CSR_TOHOST:       de_csr_val = csr_tohost;
     `CSR_FROMHOST:     de_csr_val = csr_fromhost;

     `CSR_CYCLE:        de_csr_val = csr_cycle;
     `CSR_TIME:         de_csr_val = csr_time;
     `CSR_INSTRET:      de_csr_val = csr_instret;
     `CSR_CYCLEH:       de_csr_val = csr_cycle[63:32];
     `CSR_TIMEH:        de_csr_val = csr_time[63:32];
     `CSR_INSTRETH:     de_csr_val = csr_instret[63:32];
     default:           de_csr_val = 'h X;
     endcase

//// EXECUTE ////

   reg  [31:0] ex_inst, ex_load_addr;

   reg  [11:0] ex_csrd;
   reg  [31:0] ex_csr_res;

   always @(posedge clk) begin
      ex_valid     <= de_valid & !reset & !interrupt;
      ex_inst      <= de_inst;
      ex_load_addr <= de_load_addr;
      ex_csrd      <= de_csrd;
   end

   wire [`MEMWORDS_LG2-1:0] ex_load_ea = ex_load_addr[`MEMWORDS_LG2+1:2];


   // XXX It would be easy to support unaligned memory
   // with this setup by just calculating a different ex_load_ea for
   // every slice and rotate the loaded word rather than just shifting
   // it. Similar for store.  Of course, IO access must still be
   // aligned as well as atomics.
   wire [31:0] ex_ld =
       ex_load_addr[31] ? readdata :
       {mem3[ex_load_ea], mem2[ex_load_ea], mem1[ex_load_ea], mem0[ex_load_ea]};
   reg  [31:0] ex_ld_shifted, ex_ld_res;

   always @(*) begin
      ex_ld_shifted = ex_ld >> (ex_load_addr[1:0] * 8);
      case (ex_inst`funct3)
         0: ex_ld_res = {{24{ex_ld_shifted[ 7]}}, ex_ld_shifted[ 7:0]};
         1: ex_ld_res = {{16{ex_ld_shifted[15]}}, ex_ld_shifted[15:0]};
         4: ex_ld_res = ex_ld_shifted[ 7:0];
         5: ex_ld_res = ex_ld_shifted[15:0];
         default: ex_ld_res = ex_ld;
      endcase
   end

   // Note, this could be done in stage DE and thus give a pipelined
   // implementation a single cycle branch penalty

   always @(posedge clk) begin
      ex_next_pc <= de_pc + 4;
      case (de_inst`opcode)
      `BRANCH: if (de_branch_taken) ex_next_pc <= de_pc + de_sb_imm;
      `JALR: ex_next_pc <= (de_rs1_val + de_i_imm) & 32 'h ffff_fffe;
      `JAL: ex_next_pc <= de_pc + de_uj_imm;
      `SYSTEM: case (de_inst`funct3)
               `SCALLSBREAK:
                   if (de_i_imm[11:0] == 12'h 800 && csr_status`S)
                       ex_next_pc <= csr_epc;
                   else
                       ex_next_pc <= csr_evec;
               endcase
      endcase

      // Interrupts
      if (interrupt)
          ex_next_pc <= csr_evec;
   end

   // XXX This violates the code style above but is trivial to fix
   reg  [31:0] ex_res;
   always @(posedge clk)
      case (de_inst`opcode)
         `OP_IMM, `OP:
            case (de_inst`funct3)
            `ADDSUB: if (de_inst[30] && de_inst`opcode == `OP)
                        ex_res <= de_rs1_val - de_rs2_val_or_imm;
                    else
                        ex_res <= de_rs1_val + de_rs2_val_or_imm;
            `SLL:  ex_res <= de_rs1_val << de_rs2_val_or_imm[4:0];
            `SLT:  ex_res <= $signed(de_rs1_val) < $signed(de_rs2_val_or_imm); // flip bit 31 of both operands
            `SLTU: ex_res <= de_rs1_val < de_rs2_val_or_imm;
            `XOR:  ex_res <= de_rs1_val ^ de_rs2_val_or_imm;
            `SR_:  if (de_inst[30])
                      ex_res <= $signed(de_rs1_val) >>> de_rs2_val_or_imm[4:0];
                   else
                      ex_res <= de_rs1_val >> de_rs2_val_or_imm[4:0];
            `OR:   ex_res <= de_rs1_val | de_rs2_val_or_imm;
            `AND:  ex_res <= de_rs1_val & de_rs2_val_or_imm;
          endcase

         `LUI:     ex_res <=         {de_inst[31:12], 12'd0};
         `AUIPC:   ex_res <= de_pc + {de_inst[31:12], 12'd0};

         `JALR:    ex_res <= de_pc + 4;
         `JAL:     ex_res <= de_pc + 4;

         `SYSTEM:
            case (de_inst`funct3)
            `CSRRS:  begin ex_res <= de_csr_val; ex_csr_res <= de_csr_val |  de_rs1_val; end
            `CSRRC:  begin ex_res <= de_csr_val; ex_csr_res <= de_csr_val &~ de_rs1_val; end
            `CSRRW:  begin ex_res <= de_csr_val; ex_csr_res <=               de_rs1_val; end
            `CSRRSI: begin ex_res <= de_csr_val; ex_csr_res <= de_csr_val |  de_inst`rs1; end
            `CSRRCI: begin ex_res <= de_csr_val; ex_csr_res <= de_csr_val &~ de_inst`rs1; end
            `CSRRWI: begin ex_res <= de_csr_val; ex_csr_res <=               de_inst`rs1; end
            endcase
      endcase

//// WRITE BACK ////

   always @(posedge clk)
      if (ex_valid && ex_inst`rd && ex_inst`opcode != `BRANCH && ex_inst`opcode != `STORE)
         regs[ex_inst`rd] <= ex_inst`opcode == `LOAD ? ex_ld_res : ex_res;

   always @(posedge clk) begin
      if (csr_count == csr_compare)
          csr_status[24 + 7] <= 1; // INTR_TIMER

      //// outside pipeline ////

      csr_count   <= csr_count + 1;
      csr_cycle   <= csr_cycle + 1;
      csr_time    <= csr_time  + 1;
      csr_instret <= csr_instret + ex_valid;

      if (ex_valid && ex_csrd) // XXX check permissions
        case (ex_csrd)
        `CSR_FFLAGS:    csr_fcsr[4:0]      <= ex_csr_res;
        `CSR_FRM:       csr_fcsr[7:5]      <= ex_csr_res;
        `CSR_FCSR:      csr_fcsr           <= ex_csr_res;
        `CSR_SUP0:      csr_sup0           <= ex_csr_res;
        `CSR_SUP1:      csr_sup1           <= ex_csr_res;
        `CSR_EPC:       csr_epc            <= ex_csr_res & 32'h FFFFFFFC;
//      `CSR_BADVADDR:  csr_badvaddr       <= de_csr_val; // writes are ignored
        `CSR_PTBR:      csr_ptbr           <= de_csr_val & 32'h FFFFE000;
//      `CSR_ASID:      csr_asid           <= de_csr_val;
        `CSR_COUNT:     csr_count          <= de_csr_val;
        `CSR_COMPARE:   csr_compare        <= de_csr_val;
        `CSR_EVEC:      csr_evec           <= ex_csr_res & 32'h FFFFFFFC;
//      `CSR_CAUSE:     csr_cause          <= de_csr_val; // writes are ignored
        // IM,PEI,EI,PS,S
        `CSR_STATUS:    csr_status         <= de_csr_val & 32'h 00FF000F;
//      `CSR_HARTID:    csr_hartid         <= de_csr_val; // writes are ignored
//      `CSR_IMPL:      csr_hartid         <= de_csr_val; // writes are ignored
//      `CSR_FATC:      csr_fatc           <= de_csr_val;
//      `CSR_SEND_IPI:  csr_send_ipi       <= de_csr_val;
//      `CSR_CLEAR_IPI: csr_clear_ipi      <= de_csr_val;
        `CSR_TOHOST:    $display("TOHOST %d", ex_csr_res);
        `CSR_FROMHOST:  csr_fromhost       <= de_csr_val;

        `CSR_CYCLE:     csr_cycle          <= de_csr_val;
        `CSR_TIME:      csr_time           <= de_csr_val;
        `CSR_INSTRET:   csr_instret        <= de_csr_val;
        `CSR_CYCLEH:    csr_cycle[63:32]   <= de_csr_val;
        `CSR_TIMEH:     csr_time[63:32]    <= de_csr_val;
        `CSR_INSTRETH:  csr_instret[63:32] <= de_csr_val;
        endcase

      if (de_inst`opcode == `SYSTEM &&
          de_inst`funct3 == `SCALLSBREAK &&
          (de_i_imm[11:0] == 12'h 800 && csr_status`S)) begin

          csr_status`S   <= csr_status`PS;
          csr_status`EI  <= csr_status`PEI;
      end

      if (interrupt ||
          (de_inst`opcode == `SYSTEM &&
           de_inst`funct3 == `SCALLSBREAK &&
           (de_i_imm[11:0] != 12'h 800 || !csr_status`S))) begin

          csr_epc        <= de_pc;
          csr_status`PS  <= csr_status`S;
          csr_status`S   <= 1;
          csr_status`PEI <= csr_status`EI;
          csr_status`EI  <= 0;
          csr_cause      <= interrupt ? interrupt_cause
                                      : `TRAP_SYSTEM_CALL | de_i_imm[0];
      end

    end

//// MEMORY ACCESS ////
   always @(posedge clk) if (de_store_local) begin
      if (de_byteena[0]) mem0[de_store_ea] <= de_rs2_val_shl[ 7: 0];
      if (de_byteena[1]) mem1[de_store_ea] <= de_rs2_val_shl[15: 8];
      if (de_byteena[2]) mem2[de_store_ea] <= de_rs2_val_shl[23:16];
      if (de_byteena[3]) mem3[de_store_ea] <= de_rs2_val_shl[31:24];
   end

   always @(*) begin
     writedata   = de_rs2_val_shl;
     byteena     = de_byteena;
     writeenable = de_store;
     readenable  = de_valid && de_inst`opcode == `LOAD /* && de_store_addr[31] */;
     address     = de_store ? de_store_addr[31:2] : de_load_addr[31:2];
   end

   initial begin
     $readmemh("initregs.txt", regs);
     $readmemh("program.txt", code_mem);
     $readmemh("mem0.txt", mem0);
     $readmemh("mem1.txt", mem1);
     $readmemh("mem2.txt", mem2);
     $readmemh("mem3.txt", mem3);
   end


`ifdef SIMULATION
   reg  [31:0] ex_pc, ex_sb_imm, ex_i_imm, ex_s_imm, ex_uj_imm;

   always @(posedge clk) begin
      ex_pc        <= de_pc;
      ex_sb_imm    <= de_sb_imm;
      ex_i_imm     <= de_i_imm;
      ex_s_imm     <= de_s_imm;
      ex_uj_imm    <= de_uj_imm;
   end

   always @(posedge clk)
      case (de_inst`opcode)
      `LOAD: if (/*!de_load_addr[31] &&*/
                 de_load_addr[31:`MEMWORDS_LG2+2] != (`DATA_START >> (`MEMWORDS_LG2 + 2)))
                 $display("LOAD from %x is outside mapped memory (%x)",
                          de_load_addr, de_load_addr[28:`MEMWORDS_LG2]);
      `STORE:
             if (de_store_addr[31:`MEMWORDS_LG2+2] != (`DATA_START >> (`MEMWORDS_LG2 + 2)))
                 $display("STORE to %x is outside mapped memory (%x != %x)",
                          de_store_addr,
                          de_store_addr[31:`MEMWORDS_LG2+2], (`DATA_START >> (`MEMWORDS_LG2 + 2)));
      endcase

   always @(posedge clk) begin
      if (ex_valid)
         case (ex_inst`opcode)
          `BRANCH:
              case (ex_inst`funct3)
              0: $display("%x beq    r%1d, r%1d, %x", ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              1: $display("%x bne    r%1d, r%1d, %x", ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              4: $display("%x blt    r%1d, r%1d, %x", ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              5: $display("%x bge    r%1d, r%1d, %x", ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              6: $display("%x bltu   r%1d, r%1d, %x", ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              7: $display("%x bgeu   r%1d, r%1d, %x", ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              endcase

          `OP_IMM: case (ex_inst`funct3)
              `ADDSUB:
                 if (ex_inst == 32 'h 00000013)
                       $display("%x nop", ex_pc);
                 else
                       $display("%x addi   r%1d, r%1d, %1d", ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `SLL:    $display("%x slli   r%1d, r%1d, %1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_i_imm[4:0]);
              `SLT:    $display("%x slti   r%1d, r%1d, %1d", ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `SLTU:   $display("%x sltui  r%1d, r%1d, %1d", ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `XOR:    $display("%x xori   r%1d, r%1d, %1d", ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `SR_:  if (ex_inst[30])
                       $display("%x srai   r%1d, r%1d, %1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_i_imm[4:0]);
                     else
                       $display("%x srli   r%1d, r%1d, %1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_i_imm[4:0]);
              `OR:     $display("%x ori    r%1d, r%1d, %1d", ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `AND:    $display("%x andi   r%1d, r%1d, %1d", ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              default: $display("%x OP_IMM %1d", ex_pc, ex_inst`funct3);
              endcase

          `OP: case (ex_inst`funct3)
              `ADDSUB: if (ex_inst[30])
                       $display("%x sub    r%1d, r%1d, r%1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
                     else
                       $display("%x add    r%1d, r%1d, r%1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SLL:    $display("%x sll    r%1d, r%1d, r%1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SLT:    $display("%x slt    r%1d, r%1d, r%1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SLTU:   $display("%x sltu   r%1d, r%1d, r%1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `XOR:    $display("%x xor    r%1d, r%1d, r%1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SR_:  if (ex_inst[30])
                       $display("%x sra    r%1d, r%1d, r%1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
                     else
                       $display("%x srl    r%1d, r%1d, r%1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `OR:     $display("%x ori    r%1d, r%1d, r%1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `AND:    $display("%x and    r%1d, r%1d, r%1d", ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              default: $display("%x OP %1d", ex_pc, ex_inst`funct3);
              endcase

          `LUI:  $display("%x lui    r%1d, 0x%1x", ex_pc, ex_inst`rd, ex_inst[31:12] & 32'hFFFFF000);
          `AUIPC:$display("%x auipc  r%1d, 0x%1x", ex_pc, ex_inst`rd, ex_inst[31:12] & 32'hFFFFF000);

          `LOAD: case (ex_inst`funct3)
              0: $display("%x lb     r%1d, %1d(r%1d)", ex_pc, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              1: $display("%x lh     r%1d, %1d(r%1d)", ex_pc, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              2: $display("%x lw     r%1d, %1d(r%1d)", ex_pc, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              4: $display("%x lbu    r%1d, %1d(r%1d)", ex_pc, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              5: $display("%x lhu    r%1d, %1d(r%1d)", ex_pc, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              default: $display("%x l??%1d?? r%1d, %1d(r%1d)", ex_pc, ex_inst`funct3, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              endcase

          `STORE: case (ex_inst`funct3)
              0: $display("%x sb     r%1d, %1d(r%1d)", ex_pc, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              1: $display("%x sh     r%1d, %1d(r%1d)", ex_pc, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              2: $display("%x sw     r%1d, %1d(r%1d)", ex_pc, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              default: $display("%x s??%1d?? r%1d, %1d(r%1d)", ex_pc, ex_inst`funct3, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              endcase

          `JAL: $display("%x jal    r%1d, %x", ex_pc, ex_inst`rd, ex_pc + ex_uj_imm);
          `JALR: if (ex_inst`rd == 0 && ex_i_imm == 0)
                    $display("%x ret", ex_pc);
                 else
                    $display("%x jalr   r%1d, r%1d, %x", ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));

         `SYSTEM:
            case (ex_inst`funct3)
            // XXX `SCALLSBREAK: these affect control-flow
            `CSRRS:  $display("%x csrrs  r%1d, csr%03X, r%1d", ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRC:  $display("%x csrrc  r%1d, csr%03X, r%1d", ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRW:  $display("%x csrrw  r%1d, csr%03X, r%1d", ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRSI: $display("%x csrrsi r%1d, csr%03X, r%1d", ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRCI: $display("%x csrrci r%1d, csr%03X, r%1d", ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRWI: $display("%x csrrwi r%1d, csr%03X, r%1d", ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            default: begin
                 $display("%x SYSTEM ? opcode %1d", ex_pc, ex_inst`funct3);
                 $finish;
              end
            endcase


          default: begin
                 $display("%x ? opcode %1d", ex_pc, ex_inst`opcode);
                 $finish;
              end
         endcase

      if (ex_valid && ex_inst`rd && ex_inst`opcode != `BRANCH && ex_inst`opcode != `STORE)
         $display("                                          r%1d <- 0x%x",
                  ex_inst`rd, ex_inst`opcode == `LOAD ? ex_ld_res : ex_res);
   end

   always @(posedge clk)
     if (de_store_local && de_byteena)
         $display("                                          [%x] <- %x/%x", de_store_addr, de_rs2_val_shl, de_byteena);
`endif
endmodule
