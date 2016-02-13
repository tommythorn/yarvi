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

module rs232tx
   ( input  wire        clock
   , input  wire  [7:0] data
   , input  wire        valid
   , output wire        ready
   , output wire        serial_out
   );

   parameter           frequency   = 0;
   parameter           bps         = 0;
   parameter           period      = (frequency + bps/2) / bps;
   // Worst-case period: 300 bps @ 500 MHz = 2 000 000 ~= 2^19
   parameter           TTYCLK_SIGN = 20; // 2^TTYCLK_SIGN > period_max * 2
   parameter           COUNT_SIGN  = 4;

   reg  [TTYCLK_SIGN:0] ttyclk      = 0; // [-4096; 4095]
   reg  [8:0]           shift_out   = 0;
   reg  [COUNT_SIGN:0]  count       = 0; // [-16; 15]

   assign               serial_out  = shift_out[0];
   assign               ready       = count[COUNT_SIGN] & ttyclk[TTYCLK_SIGN];

   always @(posedge clock)
      if (~ttyclk[TTYCLK_SIGN]) begin
         ttyclk     <= ttyclk - 1'd1;
      end else if (~count[COUNT_SIGN]) begin
         ttyclk     <= period - 2;
         count      <= count - 1'd1;
         shift_out  <= {1'b1, shift_out[8:1]};
      end else if (valid) begin
         ttyclk     <= period - 2;
         count      <= 9; // 1 start bit + 8 d + 1 stop - 1 due to SIGN trick
         shift_out  <= {data, 1'b0};
      end
endmodule
