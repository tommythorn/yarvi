// -----------------------------------------------------------------------
//
//   Copyright 2016 Tommy Thorn - All Rights Reserved
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
      restarts.  All of this is likely to add to a critical path.



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

`define MEMWORDS_LG2 14 // 64 KiB
`define MEMWORDS (1 << `MEMWORDS_LG2)
`define INIT_PC    32'h80_0000
`define DATA_START 32'h80_0000
`ifndef INITDIR
`define INITDIR "../shared/"
`endif

module yarvi( input  wire        clock

            , output reg  [29:0] address
            , output reg         writeenable = 0
            , output reg  [31:0] writedata
            , output reg  [ 3:0] byteena
            , output reg         readenable = 0
            , input  wire [31:0] readdata // XXX Must be ready next cycle!

            , output wire        bus_req_ready
            , input  wire        bus_req_read
            , input  wire        bus_req_write
            , input  wire [31:0] bus_req_address
            , input  wire [31:0] bus_req_data
            , output reg         bus_res_valid
            , output reg  [31:0] bus_res_data

            , input  wire [11:0] bus_csr_no
            , input  wire        bus_csr_read_enable
            , input  wire        bus_csr_write_enable
            , input  wire [31:0] bus_csr_writedata
            , output reg  [31:0] bus_csr_readdata
            , output wire        bus_csr_readdata_valid
            );

   wire bus_req_read_go  = bus_req_ready & bus_req_read;
   wire bus_req_write_go = bus_req_ready & bus_req_write;
   wire bus_req_rw_go    = bus_req_read_go | bus_req_write_go;

   /* Global state */

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

      Exceptions to this are CSR cycle and time which are
      generally updated independent of what happens in the
      pipeline. */

   reg  [31:0] regs[0:31];

   reg  [ 7:0] csr_fcsr         = 0;
   reg  [63:0] csr_cycle        = 0;
   reg  [63:0] csr_time         = 0;
   reg  [63:0] csr_instret      = 0;

   reg  [31:0] csr_mstatus      = 0;
   reg  [ 7:0] csr_mie          = 0;
   reg  [31:0] csr_mtimecmp     = 0;

   reg  [31:0] csr_mtime        = 0;
   reg  [31:0] csr_mscratch     = 0;
   reg  [31:0] csr_mepc         = 0;
   reg  [31:0] csr_mcause       = 0;
   reg  [31:0] csr_mbadaddr     = 0;
   reg  [ 7:0] csr_mip          = 0;

   reg  [31:0] csr_mtohost      = 0;
   reg  [31:0] csr_mfromhost    = 0;


   wire interrupt = (csr_mie & csr_mip) != 0 && csr_mstatus`EI;
   reg [2:0] interrupt_cause;
   wire [7:0] interrupt_mask = csr_mie & csr_mip;
   /* Xilinx's ISE is broken and can't accept the following.
   always @(*)
       case (csr_mstatus`IM & csr_mstatus`IP)
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
   */

   always @(*)
     if      (interrupt_mask[0]) interrupt_cause = 0;
     else if (interrupt_mask[1]) interrupt_cause = 1;
     else if (interrupt_mask[2]) interrupt_cause = 2;
     else if (interrupt_mask[3]) interrupt_cause = 3;
     else if (interrupt_mask[4]) interrupt_cause = 4;
     else if (interrupt_mask[5]) interrupt_cause = 5;
     else if (interrupt_mask[6]) interrupt_cause = 6;
     else interrupt_cause = 7;

   /* Forward declarations */
   reg         ex_restart          = 1;
   reg  [31:0] ex_next_pc          = `INIT_PC;
   reg         ex_valid_           = 0;
   wire        ex_valid            = ex_valid_;
   reg  [31:0] ex_inst;
   reg         ex_wben;
   reg  [31:0] ex_wbv;

   reg  [31:0] wb_inst;
   reg         wb_wben;
   reg  [31:0] wb_wbv;

//// INSTRUCTION FETCH ////

   reg         if_valid_           = 0;
   wire        if_valid            = if_valid_ && !ex_restart;
   reg  [31:0] if_pc               = 0;

   always @(posedge clock) begin
      if_valid_ <= if_valid || ex_restart;
      if_pc     <= ex_next_pc;

      // XXXXX
`ifdef SIMULATION2
      if (ex_restart)
         $display("%05d  RESTARTING FROM %x", $time, ex_next_pc);
`endif
   end

   wire [31:0] if_inst;

//// DECODE AND REGISTER FETCH ////

   /* If the previous cycle restarted the pipeline then this
      invalidates this stage, eg.

       IF       DE       EX
       8:sw     4:br     0:br 20  --> restart from 20
       20:add   8:-      4:-
       ...      20:add   8:-
       ...      ...      20:add

    */

   reg         de_valid_ = 0;
   wire        de_valid = de_valid_ && !ex_restart;
   reg  [31:0] de_pc;
   reg  [31:0] de_inst;

   reg  [31:0] de_csr_val;

   always @(posedge clock) begin
      de_valid_ <= if_valid;
      de_pc     <= if_pc;
      de_inst   <= if_inst;
   end

   reg  [31:0] de_rs1_val_r;
   reg  [31:0] de_rs2_val_r;

   wire        de_rs1_forward_ex = de_inst`rs1 == ex_inst`rd && ex_wben;
   wire        de_rs2_forward_ex = de_inst`rs2 == ex_inst`rd && ex_wben;
   wire        de_rs1_forward_wb = de_inst`rs1 == wb_inst`rd && wb_wben;
   wire        de_rs2_forward_wb = de_inst`rs2 == wb_inst`rd && wb_wben;

   wire [31:0] de_rs1_val      = de_rs1_forward_ex ? ex_wbv :
                                 de_rs1_forward_wb ? wb_wbv : de_rs1_val_r;
   wire [31:0] de_rs2_val      = de_rs2_forward_ex ? ex_wbv :
                                 de_rs2_forward_wb ? wb_wbv : de_rs2_val_r;

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
   wire [`MEMWORDS_LG2-1:0] de_load_wa  = de_load_addr[`MEMWORDS_LG2+1:2];
   wire [`MEMWORDS_LG2-1:0] de_store_wa = de_store_addr[`MEMWORDS_LG2+1:2];
   wire [ 3:0] de_bytemask     = de_inst`funct3 == 0 ? 4'd 1 : de_inst`funct3 == 1 ? 4'd 3 : 4'd 15;
   wire [ 3:0] de_load_byteena = de_bytemask << de_load_addr[1:0];
   wire [ 3:0] de_store_byteena = de_bytemask << de_store_addr[1:0];
   wire        de_store        = de_valid && de_inst`opcode == `STORE;
   wire        de_store_local  = de_store && de_store_addr[31:`MEMWORDS_LG2+2] == (`DATA_START >> (`MEMWORDS_LG2 + 2));
   wire        de_load        = de_valid && de_inst`opcode == `LOAD;
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

     `CSR_CYCLE:        de_csr_val = csr_cycle;
     `CSR_TIME:         de_csr_val = csr_time;
     `CSR_INSTRET:      de_csr_val = csr_instret;
     `CSR_CYCLEH:       de_csr_val = csr_cycle[63:32];
     `CSR_TIMEH:        de_csr_val = csr_time[63:32];
     `CSR_INSTRETH:     de_csr_val = csr_instret[63:32];

     `CSR_MCPUID:       de_csr_val = {2'h 0, 30'h1 << 8}; // RV32I
     `CSR_MIMPID:       de_csr_val = 'h5454; // 'TT'
     `CSR_MHARTID:      de_csr_val = 0;

     `CSR_MSTATUS:      de_csr_val = csr_mstatus;
     `CSR_MTVEC:        de_csr_val = 'h 100;
     `CSR_MTDELEG:      de_csr_val = 0;
     `CSR_MIE:          de_csr_val = csr_mie;
     `CSR_MTIMECMP:     de_csr_val = csr_mtimecmp;

     `CSR_MSCRATCH:     de_csr_val = csr_mscratch;
     `CSR_MEPC:         de_csr_val = csr_mepc;
     `CSR_MCAUSE:       de_csr_val = csr_mcause;
     `CSR_MBADADDR:     de_csr_val = csr_mbadaddr;
     `CSR_MIP:          de_csr_val = csr_mip;

     `CSR_MBASE:        de_csr_val = 0;
     `CSR_MBOUND:       de_csr_val = 0;
     `CSR_MIBASE:       de_csr_val = 0;
     `CSR_MIBOUND:      de_csr_val = 0;
     `CSR_MDBASE:       de_csr_val = 0;
     `CSR_MDBOUND:      de_csr_val = 0;

     `CSR_HTIMEW:       de_csr_val = 0; // XXX It's not clear
     `CSR_HTIMEHW:      de_csr_val = 0;

     `CSR_MTOHOST:      de_csr_val = csr_mtohost;
     `CSR_MFROMHOST:    de_csr_val = csr_mfromhost;

     default:           de_csr_val = 'h X;
     endcase

   // XXX Yeah, this code duplication isn't real clever
   always @(*)
     case (bus_csr_no)
     `CSR_FFLAGS:       bus_csr_readdata = csr_fcsr[4:0];
     `CSR_FRM:          bus_csr_readdata = csr_fcsr[7:5];
     `CSR_FCSR:         bus_csr_readdata = csr_fcsr;

     `CSR_CYCLE:        bus_csr_readdata = csr_cycle;
     `CSR_TIME:         bus_csr_readdata = csr_time;
     `CSR_INSTRET:      bus_csr_readdata = csr_instret;
     `CSR_CYCLEH:       bus_csr_readdata = csr_cycle[63:32];
     `CSR_TIMEH:        bus_csr_readdata = csr_time[63:32];
     `CSR_INSTRETH:     bus_csr_readdata = csr_instret[63:32];

     `CSR_MCPUID:       bus_csr_readdata = {2'h 0, 30'h1 << 8}; // RV32I
     `CSR_MIMPID:       bus_csr_readdata = 'h5454; // 'TT'
     `CSR_MHARTID:      bus_csr_readdata = 0;

     `CSR_MSTATUS:      bus_csr_readdata = csr_mstatus;
     `CSR_MTVEC:        bus_csr_readdata = 'h 100;
     `CSR_MTDELEG:      bus_csr_readdata = 0;
     `CSR_MIE:          bus_csr_readdata = csr_mie;
     `CSR_MTIMECMP:     bus_csr_readdata = csr_mtimecmp;

     `CSR_MSCRATCH:     bus_csr_readdata = csr_mscratch;
     `CSR_MEPC:         bus_csr_readdata = csr_mepc;
     `CSR_MCAUSE:       bus_csr_readdata = csr_mcause;
     `CSR_MBADADDR:     bus_csr_readdata = csr_mbadaddr;
     `CSR_MIP:          bus_csr_readdata = csr_mip;

     `CSR_MBASE:        bus_csr_readdata = 0;
     `CSR_MBOUND:       bus_csr_readdata = 0;
     `CSR_MIBASE:       bus_csr_readdata = 0;
     `CSR_MIBOUND:      bus_csr_readdata = 0;
     `CSR_MDBASE:       bus_csr_readdata = 0;
     `CSR_MDBOUND:      bus_csr_readdata = 0;

     `CSR_HTIMEW:       bus_csr_readdata = 0; // XXX It's not clear
     `CSR_HTIMEHW:      bus_csr_readdata = 0;

     `CSR_MTOHOST:      bus_csr_readdata = csr_mtohost;
     `CSR_MFROMHOST:    bus_csr_readdata = csr_mfromhost;

     default:           bus_csr_readdata = 'h X;
     endcase

   assign bus_csr_readdata_valid = 1;

//// EXECUTE ////

   reg  [31:0] ex_load_addr;

   reg  [11:0] ex_csrd;
   reg  [31:0] ex_csr_res;
   reg  [ 3:0] ex_load_byteena;
   wire [31:0] ex_loaded_data;

   always @(posedge clock) begin
      ex_valid_    <= de_valid;
      ex_inst      <= de_inst;
      ex_load_addr <= de_load_addr;
      ex_csrd      <= de_csrd;
      ex_load_byteena <= de_load_byteena;
   end


   // XXX It would be easy to support unaligned memory
   // with this setup by just calculating a different de_load_wa for
   // every slice and rotate the loaded word rather than just shifting
   // it. Similar for store.  Of course, IO access must still be
   // aligned as well as atomics.
   wire [31:0] ex_ld = ex_load_addr[31] ? readdata : ex_loaded_data;
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

   always @(posedge clock) begin

      ex_restart    <= 0;
      ex_next_pc    <= ex_next_pc + 4;

      if (de_valid)
        case (de_inst`opcode)
        `BRANCH:
          if (de_branch_taken) begin
            ex_restart    <= 1;
            ex_next_pc    <= de_pc + de_sb_imm;
          end
        `JALR: begin
            ex_restart    <= 1;
            ex_next_pc    <= (de_rs1_val + de_i_imm) & 32 'h ffff_fffe;
          end
        `JAL: begin
            ex_restart    <= 1;
            ex_next_pc    <= de_pc + de_uj_imm;
          end
        `SYSTEM: begin
            ex_restart    <= 1;
            case (de_inst`funct3)
               `SCALLSBREAK:
                   if (de_i_imm[11:0] == 12'h 800)
                       ex_next_pc <= csr_mepc;
                   else
                       ex_next_pc <= 'h 1C0; // Trap from machine-mode
               endcase
          end
      endcase

      // Interrupts
      if (interrupt) begin
        ex_restart    <= 1;
        ex_next_pc    <= 'h 1C0;
      end
   end

   // XXX This violates the code style above but is trivial to fix
   reg  [31:0] ex_res;
   always @(posedge clock)
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

   always @(*) ex_wbv = ex_inst`opcode == `LOAD ? ex_ld_res : ex_res;
   always @(*) ex_wben = ex_valid && ex_inst`rd &&
                         ex_inst`opcode != `BRANCH && ex_inst`opcode != `STORE;

   always @(posedge clock) begin
      if (ex_wben)
         regs[ex_inst`rd] <= ex_wbv;
      de_rs1_val_r <= regs[if_inst`rs1];
      de_rs2_val_r <= regs[if_inst`rs2];
   end

   always @(posedge clock) begin
      wb_inst <= ex_inst;
      wb_wben <= ex_wben;
      wb_wbv  <= ex_wbv;
   end

   always @(posedge clock) begin
      if (csr_mtime == csr_mtimecmp)
          csr_mip`MTIP <= 1;

      //// outside pipeline ////

      csr_cycle   <= csr_cycle + 1;
      csr_time    <= csr_time  + 1;
      csr_mtime   <= csr_mtime + 1;
      csr_instret <= csr_instret + ex_valid;

      if (ex_valid && ex_csrd && ex_inst`opcode == `SYSTEM) // XXX check permissions
        case (ex_csrd)
        `CSR_FFLAGS:    csr_fcsr[4:0]      <= ex_csr_res;
        `CSR_FRM:       csr_fcsr[7:5]      <= ex_csr_res;
        `CSR_FCSR:      csr_fcsr           <= ex_csr_res;

        `CSR_CYCLE:     csr_cycle          <= ex_csr_res;
        `CSR_TIME:      csr_time           <= ex_csr_res;
        `CSR_INSTRET:   csr_instret        <= ex_csr_res;
        `CSR_CYCLEH:    csr_cycle[63:32]   <= ex_csr_res;
        `CSR_TIMEH:     csr_time[63:32]    <= ex_csr_res;
        `CSR_INSTRETH:  csr_instret[63:32] <= ex_csr_res;

        `CSR_MSTATUS:   csr_mstatus        <= ex_csr_res;
        `CSR_MIE:       csr_mie            <= ex_csr_res;
        `CSR_MTIMECMP:  csr_mtimecmp       <= ex_csr_res;

        `CSR_MSCRATCH:  csr_mscratch       <= ex_csr_res;
        `CSR_MEPC:      csr_mepc           <= ex_csr_res;
        `CSR_MIP:       csr_mip[3]         <= ex_csr_res[3];

        `CSR_MTOHOST:    csr_mtohost       <= ex_csr_res;
        `CSR_MFROMHOST:  csr_mfromhost     <= ex_csr_res;
        endcase

      if (de_inst`opcode == `SYSTEM &&
          de_inst`funct3 == `SCALLSBREAK &&
          de_i_imm[11:0] == 12'h 800)

         csr_mstatus[8:0] <= csr_mstatus[11:3];         // POP

      if (interrupt ||
          (de_inst`opcode == `SYSTEM &&
           de_inst`funct3 == `SCALLSBREAK &&
           de_i_imm[11:0] != 12'h 800)) begin

          csr_mepc        <= de_pc;
          csr_mstatus[11:3] <= csr_mstatus[8:0];         // PUSH
          csr_mstatus`EI <= 0;
          csr_mstatus`PRV <= 3;
          csr_mcause      <= interrupt ? interrupt_cause
                                       : `TRAP_SYSTEM_CALL | de_i_imm[0];
      end

    end

//// MEMORY ACCESS ////

   wire [`MEMWORDS_LG2-1:0]
     b_addr = bus_req_rw_go ? bus_req_address[`MEMWORDS_LG2+1:2] :
              de_store_local ? de_store_wa : de_load_wa;
   wire [31:0] b_din = bus_req_write_go ? bus_req_data : de_rs2_val_shl;


   // XXX A store followed immediately by a load overlapping what was
   // stored will return the wrong data.  We _could_ forward the data
   // for the cases where the loaded data completely covers what was
   // loaded, but it would likely incur a cycle time penalty for this
   // extremely rare situation and it wouldn't help cases where
   // there's only a partial overlap.  Instead we should detect this
   // load-hit-store hazard and restart the load.  This still needs to
   // be done!
   bram_tdp #(8, `MEMWORDS_LG2, {`INITDIR,"mem0.txt"}) mem0
     ( .a_clk(clock)
     , .a_wr(1'd 0)
     , .a_addr(ex_next_pc[`MEMWORDS_LG2+1:2])
     , .a_din(8'h x)
     , .a_dout(if_inst[7:0])

     , .b_clk(clock)
     , .b_wr(de_store_local && de_store_byteena[0] || bus_req_write_go)
     , .b_addr(b_addr)
     , .b_din(b_din[7:0])
     , .b_dout(ex_loaded_data[7:0]));

   bram_tdp #(8, `MEMWORDS_LG2, {`INITDIR,"mem1.txt"}) mem1
     ( .a_clk(clock)
     , .a_wr(1'd 0)
     , .a_addr(ex_next_pc[`MEMWORDS_LG2+1:2])
     , .a_din(8'h x)
     , .a_dout(if_inst[15:8])

     , .b_clk(clock)
     , .b_wr(de_store_local && de_store_byteena[1] || bus_req_write_go)
     , .b_addr(b_addr)
     , .b_din(b_din[15:8])
     , .b_dout(ex_loaded_data[15:8]));

   bram_tdp #(8, `MEMWORDS_LG2, {`INITDIR,"mem2.txt"}) mem2
     ( .a_clk(clock)
     , .a_wr(1'd 0)
     , .a_addr(ex_next_pc[`MEMWORDS_LG2+1:2])
     , .a_din(8'h x)
     , .a_dout(if_inst[23:16])

     , .b_clk(clock)
     , .b_wr(de_store_local && de_store_byteena[2] || bus_req_write_go)
     , .b_addr(b_addr)
     , .b_din(b_din[23:16])
     , .b_dout(ex_loaded_data[23:16]));

   bram_tdp #(8, `MEMWORDS_LG2, {`INITDIR,"mem3.txt"}) mem3
     ( .a_clk(clock)
     , .a_wr(1'd 0)
     , .a_addr(ex_next_pc[`MEMWORDS_LG2+1:2])
     , .a_din(8'h x)
     , .a_dout(if_inst[31:24])

     , .b_clk(clock)
     , .b_wr(de_store_local && de_store_byteena[3] || bus_req_write_go)
     , .b_addr(b_addr)
     , .b_din(b_din[31:24])
     , .b_dout(ex_loaded_data[31:24]));

   always @(*) begin
     writedata   = de_rs2_val_shl;
     byteena     = de_store ? de_store_byteena : de_load_byteena;
     writeenable = de_store;
     readenable  = de_valid && de_inst`opcode == `LOAD && de_load_addr[31];
     address     = de_store ? de_store_addr[31:2] : de_load_addr[31:2];
   end

   assign bus_req_ready = !de_load && !de_store;
   reg ex_loaded_data_is_bus_res = 0;
   always @(posedge clock) begin
      ex_loaded_data_is_bus_res <= bus_req_read_go;
      bus_res_valid             <= ex_loaded_data_is_bus_res;
      bus_res_data              <= ex_loaded_data;
   end

   initial $readmemh({`INITDIR,"initregs.txt"}, regs);

`ifdef VERBOSE_SIMULATION
   reg  [31:0] ex_pc, ex_sb_imm, ex_i_imm, ex_s_imm, ex_uj_imm;

   always @(posedge clock) begin
      ex_pc        <= de_pc;
      ex_sb_imm    <= de_sb_imm;
      ex_i_imm     <= de_i_imm;
      ex_s_imm     <= de_s_imm;
      ex_uj_imm    <= de_uj_imm;
   end

   always @(posedge clock)
      if (de_valid)
        case (de_inst`opcode)
        `LOAD: if (/*!de_load_addr[31] &&*/
                   de_load_addr[31:`MEMWORDS_LG2+2] != (`DATA_START >> (`MEMWORDS_LG2 + 2)))
                   $display("%05d  LOAD from %x is outside mapped memory (%x)", $time,
                            de_load_addr, de_load_addr[28:`MEMWORDS_LG2]);
        `STORE:
               if (de_store_addr[31:`MEMWORDS_LG2+2] != (`DATA_START >> (`MEMWORDS_LG2 + 2)))
                   $display("%05d  STORE to %x is outside mapped memory (%x != %x)", $time,
                            de_store_addr,
                            de_store_addr[31:`MEMWORDS_LG2+2], (`DATA_START >> (`MEMWORDS_LG2 + 2)));
        endcase

   always @(posedge clock) begin
`ifdef SIMULATION_VERBOSE_PIPELINE
      $display("");
      if (ex_restart)
        $display("%05d  RESTART", $time);
      $display("%05d  IF @ %x V %d", $time, if_pc, if_valid);
      $display("%05d  DE @ %x V %d (%d %d)", $time, de_pc, de_valid, de_valid_, ex_restart);
      $display("%05d  EX @ %x V %d", $time, ex_pc, ex_valid);
`endif

      if (ex_valid)
         case (ex_inst`opcode)
          `BRANCH:
              case (ex_inst`funct3)
              0: $display("%05d  %x beq    r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              1: $display("%05d  %x bne    r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              4: $display("%05d  %x blt    r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              5: $display("%05d  %x bge    r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              6: $display("%05d  %x bltu   r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              7: $display("%05d  %x bgeu   r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              endcase

          `OP_IMM: case (ex_inst`funct3)
              `ADDSUB:
                 if (ex_inst == 32 'h 00000013)
                       $display("%05d  %x nop", $time, ex_pc);
                 else
                       $display("%05d  %x addi   r%1d, r%1d, %1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `SLL:    $display("%05d  %x slli   r%1d, r%1d, %1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_i_imm[4:0]);
              `SLT:    $display("%05d  %x slti   r%1d, r%1d, %1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `SLTU:   $display("%05d  %x sltui  r%1d, r%1d, %1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `XOR:    $display("%05d  %x xori   r%1d, r%1d, %1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `SR_:  if (ex_inst[30])
                       $display("%05d  %x srai   r%1d, r%1d, %1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_i_imm[4:0]);
                     else
                       $display("%05d  %x srli   r%1d, r%1d, %1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_i_imm[4:0]);
              `OR:     $display("%05d  %x ori    r%1d, r%1d, %1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `AND:    $display("%05d  %x andi   r%1d, r%1d, %1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              default: $display("%05d  %x OP_IMM %1d", $time, ex_pc, ex_inst`funct3);
              endcase

          `OP: case (ex_inst`funct3)
              `ADDSUB: if (ex_inst[30])
                       $display("%05d  %x sub    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
                     else
                       $display("%05d  %x add    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SLL:    $display("%05d  %x sll    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SLT:    $display("%05d  %x slt    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SLTU:   $display("%05d  %x sltu   r%1d, r%1d, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `XOR:    $display("%05d  %x xor    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SR_:  if (ex_inst[30])
                       $display("%05d  %x sra    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
                     else
                       $display("%05d  %x srl    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `OR:     $display("%05d  %x ori    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `AND:    $display("%05d  %x and    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              default: $display("%05d  %x OP %1d", $time, ex_pc, ex_inst`funct3);
              endcase

          `LUI:  $display("%05d  %x lui    r%1d, 0x%1x000", $time, ex_pc, ex_inst`rd, ex_inst[31:12]);
          `AUIPC:$display("%05d  %x auipc  r%1d, 0x%1x000", $time, ex_pc, ex_inst`rd, ex_inst[31:12]);

          `LOAD: case (ex_inst`funct3)
              0: $display("%05d  %x lb     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              1: $display("%05d  %x lh     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              2: $display("%05d  %x lw     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              4: $display("%05d  %x lbu    r%1d, %1d(r%1d)", $time, ex_pc, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              5: $display("%05d  %x lhu    r%1d, %1d(r%1d)", $time, ex_pc, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              default: $display("%05d  %x l??%1d?? r%1d, %1d(r%1d)", $time, ex_pc, ex_inst`funct3, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              endcase

          `STORE: case (ex_inst`funct3)
              0: $display("%05d  %x sb     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              1: $display("%05d  %x sh     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              2: $display("%05d  %x sw     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              default: $display("%05d  %x s??%1d?? r%1d, %1d(r%1d)", $time, ex_pc, ex_inst`funct3, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              endcase

          `JAL: $display("%05d  %x jal    r%1d, 0x%x", $time, ex_pc, ex_inst`rd, ex_pc + ex_uj_imm);
          `JALR: if (ex_inst`rd == 0 && ex_i_imm == 0)
                    $display("%05d  %x ret", $time, ex_pc);
                 else
                    $display("%05d  %x jalr   r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));

         `SYSTEM:
            case (ex_inst`funct3)
            // XXX `SCALLSBREAK: these affect control-flow
            `CSRRS:  $display("%05d  %x csrrs  r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRC:  $display("%05d  %x csrrc  r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRW:  $display("%05d  %x csrrw  r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRSI: $display("%05d  %x csrrsi r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRCI: $display("%05d  %x csrrci r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRWI: $display("%05d  %x csrrwi r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            default: begin
                 $display("%05d  %x SYSTEM ? opcode %1d", $time, ex_pc, ex_inst`funct3);
                 $finish;
              end
            endcase


          default: begin
                 $display("%05d  %x ? opcode %1d", $time, ex_pc, ex_inst`opcode);
                 $finish;
              end
         endcase

      if (ex_valid && ex_inst`rd && ex_inst`opcode != `BRANCH && ex_inst`opcode != `STORE)
         $display("%05d                                            r%1d <- 0x%x/%x", $time,
                  ex_inst`rd, ex_inst`opcode == `LOAD ? ex_ld_res : ex_res,
                  ex_load_byteena);
   end

   always @(posedge clock)
     if (de_store_local)
         $display("%05d                                            [%x] <- %x/%x", $time, de_store_addr, de_rs2_val_shl, de_store_byteena);
`endif
endmodule

// From http://danstrother.com/2010/09/11/inferring-rams-in-fpgas/
// A parameterized, inferable, true dual-port, dual-clock block RAM in Verilog.
module bram_tdp #(
    parameter DATA = 72,
    parameter ADDR = 10,
    parameter INIT = ""
) (
    // Port A
    input   wire                a_clk,
    input   wire                a_wr,
    input   wire    [ADDR-1:0]  a_addr,
    input   wire    [DATA-1:0]  a_din,
    output  reg     [DATA-1:0]  a_dout,

    // Port B
    input   wire                b_clk,
    input   wire                b_wr,
    input   wire    [ADDR-1:0]  b_addr,
    input   wire    [DATA-1:0]  b_din,
    output  reg     [DATA-1:0]  b_dout
);

// Shared memory
reg [DATA-1:0] mem [(2**ADDR)-1:0];

// Port A
always @(posedge a_clk) begin
    a_dout      <= mem[a_addr];
    if (a_wr) begin
        a_dout      <= a_din;
        mem[a_addr] <= a_din;
    end
end

// Port B
always @(posedge b_clk) begin
    b_dout      <= mem[b_addr];
    if (b_wr) begin
        b_dout      <= b_din;
        mem[b_addr] <= b_din;
    end
end

initial $readmemh(INIT,mem);
endmodule
