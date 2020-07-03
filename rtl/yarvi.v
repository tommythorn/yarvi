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
  ( input            clock
  , input            reset
  , output [`XMSB:0] debug);

   wire             fe_valid;
   wire [`VMSB:0]   fe_pc;
   wire [31:0]      fe_insn;

   wire             restart;
   wire [`VMSB:0]   restart_pc;

   wire [`VMSB:2]   code_address;
   wire [   31:0]   code_writedata;
   wire [    3:0]   code_writemask;

   yarvi_fe fe
     ( .clock                   (clock)
     , .reset                   (reset)

     , .restart                 (restart)
     , .restart_pc              (restart_pc)

     , .address                 (code_address)
     , .writedata               (code_writedata)
     , .writemask               (code_writemask)

     /* outputs */

     , .fe_valid                (fe_valid)
     , .fe_pc                   (fe_pc)
     , .fe_insn                 (fe_insn));

   yarvi_ex ex
     ( .clock                   (clock)
     , .reset                   (reset)

     , .valid                   (fe_valid & !restart)
     , .pc                      (fe_pc)
     , .insn                    (fe_insn)

     /* outputs */

     , .restart                 (restart)
     , .restart_pc              (restart_pc)

     , .code_address            (code_address)
     , .code_writedata          (code_writedata)
     , .code_writemask          (code_writemask)

     , .debug                   (debug));
endmodule
