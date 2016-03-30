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

`timescale 1ns/10ps

module test();
   reg clock, reset = 1;

   always #5 clock = ~clock;

   wire [29:0] address;
   wire [31:0] writedata;
   wire        writeenable;

   bemicrocv bemicrocv(.clk_50(clock));

   initial begin
      #12
      reset = 0;
   end
   initial
     clock = 1;
endmodule
