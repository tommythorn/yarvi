// -----------------------------------------------------------------------
//
//   Copyright 2018 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

The memory, AKA load-store, unit.  If ME_READY is asserted, it will
accent a load or store operation per cycle.  Loads will come back 1 or
more cycles.  There might be multiple memory pending at any one time
(if ME_READY allows it).

*************************************************************************/

`include "yarvi.h"

module yarvi_me( input  wire             clock

               // Core interface
               , input  wire             valid
               , input  wire             writeenable
               , input  wire [`VMSB:0]   address
               , input  wire [`XMSB:0]   writedata
               , input  wire [1:0]       sizelg2 // 1,2,4,8
               , input  wire [4:0]       readtag // ignored when writedata
               , input  wire             readsignextend

               , output wire             me_ready

               , output wire             me_readdatavalid // Have read result
               , output wire [4:0]       me_readdatatag
               , output wire [`XMSB:0]   me_readdata // Signextended

               // L2 cache and system interface ...
               );

   assign me_ready = 1;
   reg [`XMSB:0] datacache[1023:0];
   reg           pendingread = 0;
   reg [4:0]     pendingreadtag;
   reg [`XMSB:0] readdata;

   assign        me_readdatavalid = pendingread;
   assign        me_readdatatag   = pendingreadtag;
   assign        me_readdata      = pendingread;

   always @(posedge clock) begin
      pendingread <= 0;
      if (valid & me_ready)
        if (writeenable) begin

           if (address == 'h 80001000) begin
              $display("TOHOST %x", writedata[31:0]);
              $finish;
           end

           if (sizelg2 != 3) begin
              $display("Oops, can only handle 64-bit stores, not %d", sizelg2);
              $finish;
           end

           $display("[%x] <- %x", address[12:0], writedata);
           datacache[address[12:3]] <= writedata;
        end else begin
           if (sizelg2 != 3) begin
              $display("Oops, can only handle 64-bit loads, not %d", sizelg2);
              $finish;
           end

           pendingread <= 1;
           pendingreadtag <= readtag;
           readdata <= datacache[address[12:0]];
        end
   end
endmodule
