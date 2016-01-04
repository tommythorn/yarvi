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
//**********************************************************************
// Bridge a simple serial protocol with an Avalon bus
//**********************************************************************

/* Protocol:
 *   'a' A0 A1 A2 A3       -- set the address
 *   'r' -> D0 D1 D2 D3    -- read from address and advance by four
 *   'w' D0 D1 D2 D3       -- write to address and advance by four
 */

module htif ( input  wire        clock

            // from host

            , output wire        rx_ready
            , input  wire        rx_valid
            , input  wire  [7:0] rx_data

            // to bus

            , input  wire        bus_req_ready
            , output wire        bus_req_read
            , output wire        bus_req_write
            , output reg  [31:0] bus_req_address = 0
            , output wire [31:0] bus_req_data

            // from bus

            , input  wire        bus_res_valid
            , input  wire [31:0] bus_res_data

            // to host

            , input  wire        tx_ready
            , output wire        tx_valid
            , output reg   [7:0] tx_data

	    // debug
            , output reg [3:0]   s = 0

            );


//   reg [3:0] s = 0;
   reg [31:0] data = 0;
   reg [ 7:0] cmd;

   assign    rx_ready      = s <  5;
   assign    bus_req_read  = s == 5 && cmd == "r";
   assign    bus_req_write = s == 5 && cmd == "w";
   assign    bus_req_data  = data;
   assign    tx_valid      = s >  6;

   // fhx, from host transaction
   wire      rx_go = rx_ready & rx_valid;
   wire      tx_go = tx_ready & tx_valid;

   always @(posedge clock)
     case (s)
       0: begin
          cmd <= rx_data;
          if (rx_go && (rx_data == "a" || rx_data == "w"))
            s <= 4'd 1;
          if (rx_go && rx_data == "r")
            s <= 4'd 5;
       end

       1: if (rx_go)
            {data[ 7: 0],s} <= {rx_data,4'd 2};

       2: if (rx_go)
            {data[15: 8],s} <= {rx_data,4'd 3};

       3: if (rx_go)
            {data[23:16],s} <= {rx_data,4'd 4};

       4: if (rx_go)
            if (cmd == "a") begin
               bus_req_address <= {rx_data,data[23:0]};
               s <= 4'd 0;
            end
            else
              {data[31:24],s} <= {rx_data,4'd 5};

       5: if (bus_req_ready) begin
            if (cmd != "a")
               bus_req_address <= bus_req_address + 4;
            if (cmd == "r")
               s <= 4'd 6;
            else
               s <= 4'd 0;
          end

       6: if (bus_res_valid)
            {data,tx_data,s} <= {bus_res_data,bus_res_data[ 7: 0],4'd 7};

       7: if (tx_go)
            {tx_data,s} <= {data[15: 8],4'd 8};

       8: if (tx_go)
            {tx_data,s} <= {data[23:16],4'd 9};

       9: if (tx_go)
            {tx_data,s} <= {data[31:24],4'd 10};

       10: if (tx_go)
         s <= 0;
     endcase
endmodule
