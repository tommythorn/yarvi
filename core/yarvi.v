// -----------------------------------------------------------------------
//
//   Copyright 2016,2018 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a simple RISC-V RV64I implementation.

*************************************************************************/

`include "yarvi.h"

module yarvi
  ( input  wire             clock
  , input  wire             reset

  , output reg     [ 1:0]   me_priv
  , output wire             me_valid
  , output wire [`VMSB:0]   me_pc
  , output reg     [31:0]   me_insn
  , output wire    [ 4:0]   me_wb_rd
  , output wire [`XMSB:0]   me_wb_val
  );

   wire [`VMSB:0]   fe_pc;
   wire [31:0]      fe_insn;

/* verilator lint_off UNUSED */
   wire             rf_valid;
/* verilator lint_on UNUSED */
   wire [`VMSB:0]   rf_pc;
   wire [31:0]      rf_insn;
   wire [`VMSB:0]   rf_rs1_val;
   wire [`VMSB:0]   rf_rs2_val;

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

   wire             me_valid;
   wire [`VMSB:0]   me_pc;
   wire [4:0]       me_wb_rd;
   wire [`XMSB:0]   me_wb_val;
   wire             me_exc_misaligned;
   wire [`XMSB:0]   me_exc_mtval;
   wire             me_load_hit_store;

   wire [`VMSB:0]   code_address;
   wire [   31:0]   code_writedata;
   wire [    3:0]   code_writemask;

   yarvi_fe fe
     ( .clock                   (clock)
     , .restart                 (ex_restart)
     , .restart_pc              (ex_restart_pc)

     , .address                 (code_address)
     , .writedata               (code_writedata)
     , .writemask               (code_writemask)

     , .fe_pc                   (fe_pc)
     , .fe_insn                 (fe_insn));

   yarvi_rf rf
     ( .clock                   (clock)

     , .pc                      (fe_pc)
     , .insn                    (fe_insn)

     , .wb_rd                   (me_wb_rd)
     , .wb_val                  (me_wb_val)

     , .rf_pc                   (rf_pc)
     , .rf_insn                 (rf_insn)
     , .rf_rs1_val              (rf_rs1_val)
     , .rf_rs2_val              (rf_rs2_val));

   yarvi_ex ex
     ( .clock                   (clock)
     , .reset                   (reset)
     , .pc                      (rf_pc)
     , .insn                    (rf_insn)
     , .rs1_val                 (rf_rs1_val)
     , .rs2_val                 (rf_rs2_val)

     , .me_wb_rd                (me_wb_rd)
     , .me_wb_val               (me_wb_val)
     , .me_exc_misaligned       (me_exc_misaligned)
     , .me_exc_mtval            (me_exc_mtval)
     , .me_load_hit_store       (me_load_hit_store)

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

     , .rf_valid                (rf_valid)
     );

   yarvi_me me
     ( .clock                   (clock)

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
     );

   /* XXX Writeback/Commit */

   always @(posedge clock) me_priv <= ex_priv;
   always @(posedge clock) me_insn <= ex_insn;

/*
     if (0)
     $display("%5d  EX WBV %x:r%1d<-%x  ME WBV %x:r%1d<-%x", $time/10,
              ex_pc, ex_wb_rd, ex_wb_val,
              me_pc, me_wb_rd, me_wb_val);
*/
`ifdef DISASSEMBLE
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
