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

`timescale 1ns/10ps

module toplevel();
   reg clock = 1;
   reg reset = 1;

   always #5 clock = ~clock;


   wire        tx_ready;
   wire        tx_valid = 0;
   wire  [7:0] tx_data;

   wire        rx_ready = 1;
   wire        rx_valid;
   wire  [7:0] rx_data;

   yarvi_soc yarvi_soc
     ( .clock           (clock)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)
     );


   initial begin
      #10
      reset = 0;

      #500000
	$display("TIMED OUT");
      $finish;
   end
endmodule
