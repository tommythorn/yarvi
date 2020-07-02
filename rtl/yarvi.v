// -----------------------------------------------------------------------
//
//   Copyright 2016,2018,2020 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

YARVI2 is currently a classic four stage implementation:

       _________________    ___
      /                 \  /   \
     v                   \v     \
    FE --> DE/RF/CSR --> EX --> ME
              ^   ^      /      /
               \   \____/      /
                \_____________/

Since CSRXX instruction read the CSR file in DE but written in EX,
there's a potential RAW hazard if the CSR file was updated in EX.
For simplicity, we thus restart on user CSR writes, but a better
alternative might be for DE to detect this and insert a bubble between
two CSR instructions.

*************************************************************************/

`include "yarvi.h"

module yarvi
  ( input  wire             clock
  , input  wire             reset

  , input  wire             freeze

  , output wire             me_valid
  , output reg     [ 1:0]   me_priv
  , output wire [`VMSB:0]   me_pc
  , output reg     [31:0]   me_insn
  , output wire    [ 4:0]   me_wb_rd
  , output wire [`XMSB:0]   me_wb_val
  );

   wire             fe_valid;
   wire [`VMSB:0]   fe_pc;
   wire [31:0]      fe_insn;

   wire             ex_valid;
   wire [`VMSB:0]   ex_pc;
   wire [31:0]      ex_insn;
   wire [ 1:0]      ex_priv;

   wire             ex_restart;
   wire [`VMSB:0]   ex_restart_pc;

   wire [ 4:0]      ex_wb_rd;
   wire [`VMSB:0]   ex_wb_val;

   wire             ex_readenable;
   wire             ex_writeenable;
   wire [ 2:0]      ex_funct3;
   wire [`XMSB:0]   ex_writedata;

   wire             me_exc_misaligned;
   wire [`XMSB:0]   me_exc_mtval;
   wire             me_load_hit_store;
   wire             me_timer_interrupt;

   wire [`VMSB:2]   code_address;
   wire [   31:0]   code_writedata;
   wire [    3:0]   code_writemask;

   yarvi_fe fe
     ( .clock                   (clock)
     , .reset                   (reset)
     , .restart                 (ex_restart)
     , .restart_pc              (ex_restart_pc)

     , .address                 (code_address)
     , .writedata               (code_writedata)
     , .writemask               (code_writemask)

     , .fe_valid                (fe_valid)
     , .fe_pc                   (fe_pc)
     , .fe_insn                 (fe_insn));

   yarvi_ex ex
     ( .clock                   (clock)
     , .reset                   (reset)

     , .valid                   (fe_valid & !ex_restart)
     , .pc                      (fe_pc)
     , .insn                    (fe_insn)

     , .wb_valid                (me_valid)
     , .wb_rd                   (me_wb_rd)
     , .wb_val                  (me_wb_val)

     , .me_pc                   (me_pc)
     , .me_wb_rd                (me_wb_rd)
     , .me_wb_val               (me_wb_val)
     , .me_exc_misaligned       (me_exc_misaligned)
     , .me_exc_mtval            (me_exc_mtval)
     , .me_load_hit_store       (me_load_hit_store | freeze)
     , .me_timer_interrupt      (me_timer_interrupt)

     , .ex_valid                (ex_valid)
     , .ex_pc                   (ex_pc)
     , .ex_insn                 (ex_insn)
     , .ex_priv                 (ex_priv)

     , .ex_restart              (ex_restart)
     , .ex_restart_pc           (ex_restart_pc)

     , .ex_wb_rd                (ex_wb_rd)
     , .ex_wb_val               (ex_wb_val)

     , .ex_readenable           (ex_readenable)
     , .ex_writeenable          (ex_writeenable)
     , .ex_funct3               (ex_funct3)
     , .ex_writedata            (ex_writedata)
     );

   yarvi_me me
     ( .clock                   (clock)
     , .reset                   (reset)

     , .valid                   (ex_valid)
     , .pc                      (ex_pc)
     , .wb_rd                   (ex_wb_rd)
     , .wb_val                  (ex_wb_val)

     , .readenable              (ex_readenable)
     , .writeenable             (ex_writeenable)
     , .funct3                  (ex_funct3)
     , .writedata               (ex_writedata)

     , .code_address            (code_address)
     , .code_writedata          (code_writedata)
     , .code_writemask          (code_writemask)

     , .me_valid                (me_valid)
     , .me_pc                   (me_pc)
     , .me_wb_rd                (me_wb_rd)
     , .me_wb_val               (me_wb_val)
     , .me_exc_misaligned       (me_exc_misaligned)
     , .me_exc_mtval            (me_exc_mtval)
     , .me_load_hit_store       (me_load_hit_store)
     , .me_timer_interrupt      (me_timer_interrupt)
     );

   /* XXX Writeback/Commit */

   always @(posedge clock) me_priv <= ex_priv;
   always @(posedge clock) me_insn <= ex_insn;

/*
   always @(posedge clock)
     $display("%5d  EX WBV %x:r%1d<-%x  ME WBV %x:r%1d<-%x", $time/10,
              ex_pc, ex_wb_rd, ex_wb_val,
              me_pc, me_wb_rd, me_wb_val);
*/

`ifdef DISASSEMBLE_disabled_for_now
   yarvi_disass disass
     ( .clock                   (clock)
     , .info                    ({ex_restart,rf_valid, ex_valid, me_valid})
     , .valid                   (me_valid)
     , .prv                     (me_priv)
     , .pc                      (me_pc)
     , .insn                    (me_insn)
     , .wb_rd                   (me_wb_rd)
     , .wb_val                  (me_wb_val));
`endif
endmodule
