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

/*
 * This RS232 receiver only offers a single element buffer, and
 * as we obviously can't offer backpressure it is the resposibility
 * of the receiver to avoid overflow.
 */

module rs232rx
   ( input  wire        clock
   , output reg   [7:0] data = 0
   , output reg         valid = 0
   , input  wire        ready
   , input  wire        serial_in
   , output reg         overflow = 0
   );

   parameter           frequency  = 25_000_000;
   parameter           bps        =     57_600;
   parameter           period     = (frequency + bps/2) / bps;
   // Worst-case period: 300 bps @ 500 MHz = 2 000 000 ~= 2^19
   parameter           TTYCLK_SIGN = 20; // 2^TTYCLK_SIGN > period_max * 2
   parameter           COUNT_SIGN  = 4;

   reg  [TTYCLK_SIGN:0] ttyclk      = 0; // [-4096; 4095]
   reg  [COUNT_SIGN:0]  count       = 0; // [-16; 15]
   reg  [ 7:0]          shift_in    = 0;
   reg                  rxd         = 0;
   reg                  rxd2        = 0;

   /*
    * The theory: look for a negedge, then wait 1.5 bit period to skip
    * start bit and center in first bit.  Keep shifting bits until a full
    * byte is collected.
    *
    *        Start                        Stop
    * q      ~\__ B0 B1 B2 B3 B4 B5 B6 B7 ~~
    * count        8  7  6  5  4  3  2  1
    */
   always @(posedge clock) begin
      if (ready) begin
         valid <= 0;
         overflow <= 0;
      end

      // Get rid of meta stability.
      {rxd2,rxd} <= {rxd,serial_in};

      if (~ttyclk[TTYCLK_SIGN]) begin
         ttyclk <= ttyclk - 1'd1;
      end else if (count) begin
         if (count == 1) begin
            data <= {rxd2, shift_in[7:1]};
            if (valid & !ready)
              overflow <= 1;
            valid <= 1;
         end

         count       <= count - 1'd1;
         shift_in    <= {rxd2, shift_in[7:1]}; // Shift in from the left
         ttyclk      <= period - 2;
      end else if (~rxd2) begin
         // Just saw the negedge of the start bit
         ttyclk      <= (3 * period) / 2 - 2;
         count       <= 8;
      end
   end
endmodule
