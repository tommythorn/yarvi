// -----------------------------------------------------------------------
//
//   Copyright 2016,2018 Tommy Thorn - All Rights Reserved
//
//   This program is free software; you can redistribute it and/or modify
//   it under the terms of the GNU General Public License as published by
//   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
//   Bostom MA 02111-1307, USA; either version 2 of the License, or
//   (at your option) any later version; incorporated herein by reference.
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a relatively simple RISC-V RV32 implementation, currently only
RV32I is supported though.

*************************************************************************/


`timescale 1ns/10ps

`include "riscv.h"

`define MEMWORDS_LG2 15 // 128 KiB
`define MEMWORDS (1 << `MEMWORDS_LG2)
`define INIT_PC    32'h8000_0000 // XXX should be 'h 1000 but we don't have memory there yet
`define DATA_START 32'h8000_0000
`ifndef INITDIR
`define INITDIR ""
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

`ifdef DEBUG_HTIF
   always @(posedge clock)
     if (bus_res_valid)
       $display("BUS RESULT DATA %x", bus_res_data);

   always @(posedge clock)
     if (bus_req_read_go)
       $display("BUS READ REQ FOR ADDRESS %x", bus_req_address);

   always @(posedge clock)
     if (bus_req_write_go)
       $display("BUS WRITE REQ FOR ADDRESS %x DATA %x", bus_req_address, bus_res_data);
`endif

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

   // All CSRs can be accessed by csrXX instructions, but some are
   // used directly by the pipeline, as annotated below.

   // URW
   reg  [ 4:0] csr_fflags       = 0;
   reg  [ 2:0] csr_frm          = 0;
   // URO
   reg  [63:0] csr_cycle        = 0;
   reg  [63:0] csr_time         = 0;
   reg  [63:0] csr_instret      = 0;

   // MRO, Machine Information Registers
   reg  [31:0] csr_mcpuid       = 1 << 8; // RV32I
   reg  [31:0] csr_mimpid       = 'h5454; // 'TT'
   reg  [31:0] csr_mhartid      = 0;
   // MRW, Machine Trap Setup
   reg  [31:0] csr_mstatus      = {2'd 3, 1'd 0};
   reg  [31:0] csr_mtvec        = 'h 100;
   reg  [31:0] csr_mtdeleg      = 0;
   reg  [ 7:0] csr_mie          = 0;
   reg  [31:0] csr_mtimecmp     = 0;
   // MRW, Machine Time and Counters
   reg  [31:0] csr_mtime        = 0;
   // MRW, Machine Trap Handling
   reg  [31:0] csr_mscratch     = 0;
   reg  [31:0] csr_mepc         = 0;
   reg  [31:0] csr_mcause       = 0;
   reg  [31:0] csr_mbadaddr     = 0;
   reg  [ 7:0] csr_mip          = 0;
   // MRW, Machine Host-Target Interface (Non-Standard Berkeley Extension)
   reg  [31:0] csr_mtohost      = 0;
   reg  [31:0] csr_mfromhost    = 0;


   wire       interrupt      = (csr_mie & csr_mip) != 0 && csr_mstatus`EI;
   wire [7:0] interrupt_mask = csr_mie & csr_mip;
   reg  [2:0] interrupt_cause;

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

   reg         wb_valid            = 0;
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
   wire        de_illegal_csr_access = de_valid && de_inst`opcode == `SYSTEM && de_inst`funct3 != `PRIV &&
                       (csr_mstatus`PRV < de_inst[29:28] ||
                        de_inst[31:30] == 3 && (de_inst`funct3 != `CSRRS || de_inst`rs1 != 0));

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
   wire [31:0] de_s_imm        = {de_sign20, de_inst`funct7, de_inst`rd};
   wire [31:0] de_sb_imm       = {de_sign20, de_inst[7], de_inst[30:25], de_inst[11:8], 1'd0};

   // U-type
   wire [31:0] de_uj_imm       = {de_sign12, de_inst[19:12], de_inst[20], de_inst[30:21], 1'd0};

   wire [31:0] de_rs2_val_imm  = de_inst`opcode == `OP_IMM ? de_i_imm : de_rs2_val;

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
     case (de_inst`funct3)
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
     `CSR_FFLAGS:       de_csr_val = csr_fflags;
     `CSR_FRM:          de_csr_val = csr_frm;
     `CSR_FCSR:         de_csr_val = {csr_frm, csr_fflags};

     `CSR_CYCLE:        de_csr_val = csr_cycle;
     `CSR_TIME:         de_csr_val = csr_time;
     `CSR_INSTRET:      de_csr_val = csr_instret;
     `CSR_CYCLEH:       de_csr_val = csr_cycle[63:32];
     `CSR_TIMEH:        de_csr_val = csr_time[63:32];
     `CSR_INSTRETH:     de_csr_val = csr_instret[63:32];

     `CSR_MCPUID:       de_csr_val = csr_mcpuid;
     `CSR_MIMPID:       de_csr_val = csr_mimpid;
     `CSR_MHARTID:      de_csr_val = csr_mhartid;

     `CSR_MSTATUS:      de_csr_val = csr_mstatus;
     `CSR_MTVEC:        de_csr_val = csr_mtvec;
     `CSR_MTDELEG:      de_csr_val = csr_mtdeleg;
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
     `CSR_FFLAGS:       bus_csr_readdata = csr_fflags;
     `CSR_FRM:          bus_csr_readdata = csr_frm;
     `CSR_FCSR:         bus_csr_readdata = {csr_frm, csr_fflags};

     `CSR_CYCLE:        bus_csr_readdata = csr_cycle;
     `CSR_TIME:         bus_csr_readdata = csr_time;
     `CSR_INSTRET:      bus_csr_readdata = csr_instret;
     `CSR_CYCLEH:       bus_csr_readdata = csr_cycle[63:32];
     `CSR_TIMEH:        bus_csr_readdata = csr_time[63:32];
     `CSR_INSTRETH:     bus_csr_readdata = csr_instret[63:32];

     `CSR_MCPUID:       bus_csr_readdata = csr_mcpuid;
     `CSR_MIMPID:       bus_csr_readdata = csr_mimpid;
     `CSR_MHARTID:      bus_csr_readdata = csr_mhartid;

     `CSR_MSTATUS:      bus_csr_readdata = csr_mstatus;
     `CSR_MTVEC:        bus_csr_readdata = csr_mtvec;
     `CSR_MTDELEG:      bus_csr_readdata = csr_mtdeleg;
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

//// WRITEBACK ////

   reg  [11:0] wb_csrd;

   always @(posedge clock) begin
      ex_valid_       <= de_valid & !de_illegal_csr_access;
      ex_inst         <= de_inst;
      ex_load_addr    <= de_load_addr;
      ex_csrd         <= de_csrd;
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
      if (ex_restart)
         $display("%05d  RESTARTING FROM %x", $time, ex_next_pc);

      ex_restart    <= 0;
      ex_next_pc    <= ex_next_pc + 4;

      // Restart if the previous instruction wrote a CSR or was fence.i
      if (de_valid && (de_inst`opcode == `SYSTEM && de_csrd ||
                       de_inst`opcode == `MISC_MEM)) begin
         ex_restart <= 1;
         ex_next_pc <= de_pc + 4;
      end

      // Take exception on illegal CSR access
      if (de_illegal_csr_access) begin
         ex_restart <= 1;
         ex_next_pc <= csr_mtvec + csr_mstatus`PRV * 'h 40;
      end

      case ({!de_valid & !interrupt,de_inst`opcode})
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
           case (de_inst`funct3)
           `PRIV:
             begin
                ex_restart    <= 1;
                case (de_inst`imm11_0)
                  `ECALL: ex_next_pc <= csr_mtvec + csr_mstatus`PRV * 'h 40;
                  `ERET:  ex_next_pc <= csr_mepc; //$display("        ERET -> %x", csr_mepc);
                  `EBREAK: $finish; // XXX
                  default: begin
                     $display("NOT IMPLEMENTED");
                     $finish;
                  end
                endcase
             end
           endcase
           end
      endcase

      // Interrupts
      if (interrupt) begin
        ex_restart    <= 1;
        ex_next_pc    <= csr_mtvec + csr_mstatus`PRV * 'h 40;
      end
   end

   // XXX This violates the code style above but is trivial to fix
   reg  [31:0] ex_res;
   always @(posedge clock)
      case (de_inst`opcode)
         `OP_IMM, `OP:
            case (de_inst`funct3)
            `ADDSUB: if (de_inst[30] && de_inst`opcode == `OP)
                        ex_res <= de_rs1_val - de_rs2_val_imm;
                    else
                        ex_res <= de_rs1_val + de_rs2_val_imm;
            `SLL:  ex_res <= de_rs1_val << de_rs2_val_imm[4:0];
            `SLT:  ex_res <= $signed(de_rs1_val) < $signed(de_rs2_val_imm); // flip bit 31 of both operands
            `SLTU: ex_res <= de_rs1_val < de_rs2_val_imm;
            `XOR:  ex_res <= de_rs1_val ^ de_rs2_val_imm;
            `SR_:  if (de_inst[30])
                      ex_res <= $signed(de_rs1_val) >>> de_rs2_val_imm[4:0];
                   else
                      ex_res <= de_rs1_val >> de_rs2_val_imm[4:0];
            `OR:   ex_res <= de_rs1_val | de_rs2_val_imm;
            `AND:  ex_res <= de_rs1_val & de_rs2_val_imm;
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
      wb_valid <= ex_valid;
      wb_inst <= ex_inst;
      wb_wben <= ex_wben;
      wb_wbv  <= ex_wbv;
      wb_csrd <= ex_csrd;
   end

   always @(posedge clock) begin
      if (csr_mtime == csr_mtimecmp) begin
         $display("Times up!");
         if (!csr_mie`MTIP)
           $display("  but the interrupt currently disabled");
         csr_mip`MTIP <= 1;
      end

      //// outside pipeline ////

      csr_cycle   <= csr_cycle + 1;
      csr_time    <= csr_time  + 1;
      csr_mtime   <= csr_mtime + 1;
      csr_instret <= csr_instret + ex_valid;

      //// CSR updates ////

      if (de_illegal_csr_access)
        $display("%05d  exception: illegal CSR access attempted %x %x (priviledge %d, CSR %x)",
                 $time, de_pc, de_inst, csr_mstatus`PRV, de_inst`imm11_0);

      if (ex_valid & !interrupt) begin
         if (ex_csrd && ex_inst`opcode == `SYSTEM)
           begin
           $display("          CSR%x <- %x", ex_csrd, ex_csr_res);

           case (ex_csrd)
           `CSR_FFLAGS:    csr_fflags           <= ex_csr_res;
           `CSR_FRM:       csr_frm              <= ex_csr_res;
           `CSR_FCSR:      {csr_frm,csr_fflags} <= ex_csr_res;

           `CSR_MSTATUS:   csr_mstatus          <= ex_csr_res & ~(15 << 12); // No FP or XS;
           `CSR_MIE:       csr_mie              <= ex_csr_res;
           `CSR_MTIMECMP:  csr_mtimecmp         <= ex_csr_res;

           `CSR_MSCRATCH:  csr_mscratch         <= ex_csr_res;
           `CSR_MEPC:      csr_mepc             <= ex_csr_res;
           `CSR_MIP:       csr_mip[3]           <= ex_csr_res[3];

           `CSR_MFROMHOST: csr_mfromhost        <= ex_csr_res;
           `CSR_MTOHOST:
             begin
                csr_mtohost <= ex_csr_res;
                $display("        TOHOST %x", ex_csr_res);
                $finish;
             end

           `CSR_CYCLEW:    csr_cycle           <= ex_csr_res;
           `CSR_TIMEW:     csr_time            <= ex_csr_res;
           `CSR_INSTRETW:  csr_instret         <= ex_csr_res;
           `CSR_CYCLEHW:   csr_cycle[63:32]    <= ex_csr_res;
           `CSR_TIMEHW:    csr_time[63:32]     <= ex_csr_res;
           `CSR_INSTRETHW: csr_instret[63:32]  <= ex_csr_res;
           default:
             $display("        warning: writing an unimplemented CSR");
           endcase
           end

         if (ex_inst`opcode == `SYSTEM &&
             ex_inst`funct3 == `PRIV &&
             ex_inst`imm11_0 == `ERET)

           csr_mstatus[8:0] <= csr_mstatus[11:3];         // POP
      end

      // NB: We delay the interrupt until the instruction is valid to avoid
      // complications in computing csr_mepc.  This works as long as ex_valid
      // will eventuall be set, which is _currently_ true.

      if (de_valid &&
          (interrupt ||
           de_inst`opcode == `SYSTEM &&
           de_inst`funct3 == `PRIV &&
           de_i_imm[11:0] != `ERET) ||
          de_illegal_csr_access) begin

          csr_mepc          <= de_pc;
          csr_mstatus[11:3] <= csr_mstatus[8:0];         // PUSH
          csr_mstatus`EI    <= 0;
          csr_mstatus`PRV   <= 3;
          csr_mcause        <= interrupt                 ? interrupt_cause    :
                               de_illegal_csr_access     ? `TRAP_INST_ILLEGAL :
                               de_i_imm[11:0] == `EBREAK ? `TRAP_BREAKPOINT   :
                                                           `TRAP_ECALL_UMODE + csr_mstatus`PRV;
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
      $display("%05d  EX @ %x V %d %x", $time, ex_pc, ex_valid, ex_inst);
`endif

      if (ex_valid)
         case (ex_inst`opcode)
          `BRANCH:
              case (ex_inst`funct3)
              0: $display("%05d  %x %x beq    r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              1: $display("%05d  %x %x bne    r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              4: $display("%05d  %x %x blt    r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              5: $display("%05d  %x %x bge    r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              6: $display("%05d  %x %x bltu   r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              7: $display("%05d  %x %x bgeu   r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst, ex_inst`rs1, ex_inst`rs2, ex_pc + ex_sb_imm);
              endcase

          `OP_IMM: case (ex_inst`funct3)
              `ADDSUB:
                 if (ex_inst == 32 'h 00000013)
                       $display("%05d  %x %x nop", $time, ex_pc, ex_inst);
                 else
                       $display("%05d  %x %x addi   r%1d, r%1d, %1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `SLL:    $display("%05d  %x %x slli   r%1d, r%1d, %1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_i_imm[4:0]);
              `SLT:    $display("%05d  %x %x slti   r%1d, r%1d, %1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `SLTU:   $display("%05d  %x %x sltui  r%1d, r%1d, %1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `XOR:    $display("%05d  %x %x xori   r%1d, r%1d, %1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `SR_:  if (ex_inst[30])
                       $display("%05d  %x %x srai   r%1d, r%1d, %1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_i_imm[4:0]);
                     else
                       $display("%05d  %x %x srli   r%1d, r%1d, %1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_i_imm[4:0]);
              `OR:     $display("%05d  %x %x ori    r%1d, r%1d, %1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              `AND:    $display("%05d  %x %x andi   r%1d, r%1d, %1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));
              default: $display("%05d  %x %x OP_IMM %1d", $time, ex_pc, ex_inst, ex_inst`funct3);
              endcase

          `OP: case (ex_inst`funct3)
              `ADDSUB: if (ex_inst[30])
                       $display("%05d  %x %x sub    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
                     else
                       $display("%05d  %x %x add    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SLL:    $display("%05d  %x %x sll    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SLT:    $display("%05d  %x %x slt    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SLTU:   $display("%05d  %x %x sltu   r%1d, r%1d, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `XOR:    $display("%05d  %x %x xor    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `SR_:  if (ex_inst[30])
                       $display("%05d  %x %x sra    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
                     else
                       $display("%05d  %x %x srl    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `OR:     $display("%05d  %x %x ori    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              `AND:    $display("%05d  %x %x and    r%1d, r%1d, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, ex_inst`rs2);
              default: $display("%05d  %x %x OP %1d", $time, ex_pc, ex_inst, ex_inst`funct3);
              endcase

          `LUI:  $display("%05d  %x %x lui    r%1d, 0x%1x000", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst[31:12]);
          `AUIPC:$display("%05d  %x %x auipc  r%1d, 0x%1x000", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst[31:12]);

          `LOAD: case (ex_inst`funct3)
              0: $display("%05d  %x %x lb     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              1: $display("%05d  %x %x lh     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              2: $display("%05d  %x %x lw     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              4: $display("%05d  %x %x lbu    r%1d, %1d(r%1d)", $time, ex_pc, ex_inst, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              5: $display("%05d  %x %x lhu    r%1d, %1d(r%1d)", $time, ex_pc, ex_inst, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              default: $display("%05d  %x %x l??%1d?? r%1d, %1d(r%1d)", $time, ex_pc, ex_inst, ex_inst`funct3, ex_inst`rd, $signed(ex_i_imm), ex_inst`rs1);
              endcase

          `STORE: case (ex_inst`funct3)
              0: $display("%05d  %x %x sb     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              1: $display("%05d  %x %x sh     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              2: $display("%05d  %x %x sw     r%1d, %1d(r%1d)", $time, ex_pc, ex_inst, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              default: $display("%05d  %x %x s??%1d?? r%1d, %1d(r%1d)", $time, ex_pc, ex_inst, ex_inst`funct3, ex_inst`rs2, $signed(ex_s_imm), ex_inst`rs1);
              endcase

          `JAL: $display("%05d  %x %x jal    r%1d, 0x%x", $time, ex_pc, ex_inst, ex_inst`rd, ex_pc + ex_uj_imm);
          `JALR: if (ex_inst`rd == 0 && ex_i_imm == 0)
                    $display("%05d  %x %x ret", $time, ex_pc, ex_inst);
                 else
                    $display("%05d  %x %x jalr   r%1d, r%1d, 0x%x", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`rs1, $signed(ex_i_imm));

         `SYSTEM:
            case (ex_inst`funct3)
            // XXX `PRIV: these affect control-flow
            `CSRRS:  $display("%05d  %x %x csrrs  r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRC:  $display("%05d  %x %x csrrc  r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRW:  $display("%05d  %x %x csrrw  r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRSI: $display("%05d  %x %x csrrsi r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRCI: $display("%05d  %x %x csrrci r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `CSRRWI: $display("%05d  %x %x csrrwi r%1d, csr%03X, r%1d", $time, ex_pc, ex_inst, ex_inst`rd, ex_inst`imm11_0, ex_inst`rs1);
            `PRIV: begin
               case (ex_inst`imm11_0)
               `ECALL:  $display("%05d  %x %x ecall", $time, ex_pc, ex_inst);
               `EBREAK: $display("%05d  %x %x ebreak", $time, ex_pc, ex_inst);
               `ERET:   $display("%05d  %x %x eret", $time, ex_pc, ex_inst);
               default: begin
                  $display("%05d  %x %x PRIV opcode %1d?", $time, ex_pc, ex_inst, ex_inst`imm11_0);
                  $finish;
               end
               endcase
            end
            endcase

          `MISC_MEM:
            case (ex_inst`funct3)
              `FENCE:   $display("%05d  %x %x fence", $time, ex_pc, ex_inst);
              `FENCE_I: $display("%05d  %x %x fence.i", $time, ex_pc, ex_inst);
              default: begin
                 $display("%05d  %x %x unknown", $time, ex_pc, ex_inst);
                 $finish;
              end
            endcase

          default: begin
             $display("%05d  %x %x ? opcode %1d", $time, ex_pc, ex_inst, ex_inst`opcode);
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
