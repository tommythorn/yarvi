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
  ( input  wire         clock
  , input  wire         reset
  );

   wire [`VMSB:0]   fe_pc;
   wire [31:0]      fe_insn;

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
   wire [4:0]       me_wb_rd;
   wire [`XMSB:0]   me_wb_val;

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

     , .me_valid                (me_valid)
     , .me_wb_rd                (me_wb_rd)
     , .me_wb_val               (me_wb_val)

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

     , .valid                   (ex_valid)
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
     , .me_wb_rd                (me_wb_rd)
     , .me_wb_val               (me_wb_val)
     );

   /* XXX Writeback/Commit */

   reg [ 1:0]      me_priv;
   reg [`VMSB:0]   me_pc;
   reg [31:0]      me_insn;
   always @(posedge clock) me_priv <= ex_priv;
   always @(posedge clock) me_pc   <= ex_pc;
   always @(posedge clock) me_insn <= ex_insn;

   yarvi_disass disass
     ( .clock                   (clock)
     , .valid                   (ex_valid)
     , .prv                     (ex_priv)
     , .pc                      (ex_pc)
     , .insn                    (ex_insn)
     , .wb_rd                   (ex_wb_rd)
     , .wb_val                  (ex_wb_val));
endmodule
