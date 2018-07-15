// -----------------------------------------------------------------------
//
//   Copyright 2016,2018 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a simple RISC-V RV64I implementation.

*************************************************************************/

`include "yarvi.h"

module yarvi( input  wire        clock);

   wire             ex_restart;
   wire [`VMSB:0]   ex_restart_pc;

   wire [`VMSB:0]   fe_pc;
   wire [31:0]      fe_insn;

   wire [`VMSB:0]   rf_pc;
   wire [31:0]      rf_insn;
   wire [63:0]      rf_rs1_val;
   wire [63:0]      rf_rs2_val;

   wire             ex_wben;
   wire [ 4:0]      ex_wb_rd;
   wire [63:0]      ex_wb_val;

   wire             ex_valid;
   wire [`VMSB:0]   ex_pc;
   wire [31:0]      ex_insn;

   yarvi_fe fe
     ( .clock           (clock)
     , .restart         (ex_restart)
     , .restart_pc      (ex_restart_pc)

     , .fe_pc           (fe_pc)
     , .fe_insn         (fe_insn));

   yarvi_rf rf
     ( .clock           (clock)
     , .pc              (fe_pc)
     , .insn            (fe_insn)
     , .we              (ex_wben)
     , .addr            (ex_wb_rd)
     , .d               (ex_wb_val)

     , .rf_pc           (rf_pc)
     , .rf_insn         (rf_insn)
     , .rf_rs1_val      (rf_rs1_val)
     , .rf_rs2_val      (rf_rs2_val));

   yarvi_ex ex
     ( .clock           (clock)
     , .pc              (rf_pc)
     , .insn            (rf_insn)
     , .rs1_val         (rf_rs1_val)
     , .rs2_val         (rf_rs2_val)

     , .ex_restart      (ex_restart)
     , .ex_restart_pc   (ex_restart_pc)
     , .ex_wben (ex_wben)
     , .ex_wb_val       (ex_wb_val)
     , .ex_wb_rd           (ex_wb_rd)

     , .ex_valid        (ex_valid)
     , .ex_pc           (ex_pc)
     , .ex_insn         (ex_insn));

   yarvi_disass disass
     ( .clock           (clock)
     , .valid           (ex_valid)
     , .pc              (ex_pc)
     , .insn            (ex_insn));
endmodule
