// -----------------------------------------------------------------------
//
//   Copyright 2016,2018,2020 Tommy Thorn - All Rights Reserved
//
//   This program is free software; you can redistribute it and/or modify
//   it under the terms of the GNU General Public License as published by
//   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
//   Bostom MA 02111-1307, USA; either version 2 of the License, or
//   (at your option) any later version; incorporated herein by reference.
//
// -----------------------------------------------------------------------

`default_nettype none
`timescale 1ns / 1ps
module yarvi_soc
  ( input  wire        clock
  , input  wire        reset

  // from host

  , output wire        rx_ready
  , input  wire        rx_valid
  , input  wire  [7:0] rx_data

  // to host

  , input  wire        tx_ready
  , output wire        tx_valid
  , output wire  [7:0] tx_data

  // debug
  , output wire [`VMSB:0] debug);

   assign rx_ready = 1;
   assign {tx_valid, tx_data} = debug[8:0];

   yarvi yarvi
     ( .clock           (clock)
     , .reset           (reset)

     , .debug           (debug)
     );
endmodule
