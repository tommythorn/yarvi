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
            , output wire  [3:0] htif_state
            );

   wire        bus_req_ready;
   wire        bus_req_read;
   wire [31:0] bus_req_address;
   wire        bus_req_write;
   wire [31:0] bus_req_data;

   wire        bus_res_valid;
   wire [31:0] bus_res_data;

   htif htif
     ( .clock           (clock)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)

     , .bus_req_ready   (bus_req_ready)
     , .bus_req_read    (bus_req_read)
     , .bus_req_write   (bus_req_write)
     , .bus_req_address (bus_req_address)
     , .bus_req_data    (bus_req_data)

     , .bus_res_valid   (bus_res_valid)
     , .bus_res_data    (bus_res_data)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)

     // debug
     , .s               (htif_state)
     );

   yarvi yarvi
     ( .clock           (clock)

     , .bus_req_ready   (bus_req_ready)
     , .bus_req_read    (bus_req_read)
     , .bus_req_write   (bus_req_write)
     , .bus_req_address (bus_req_address)
     , .bus_req_data    (bus_req_data)

     , .bus_res_valid   (bus_res_valid)
     , .bus_res_data    (bus_res_data)
     );
endmodule
