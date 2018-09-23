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
 *   'R' -> D0 .. D7       -- read from address and advance by eight
 *   'W' D0 .. D7       -- write to address and advance by four
 */

// XXX -> header file?
`define S_START         4'd0
`define S_CMD_AW_ADDR0  4'd1
`define S_CMD_AW_ADDR1  4'd2
`define S_CMD_AW_ADDR2  4'd3
`define S_CMD_AW_ADDR3  4'd4
`define S_CMD_RD_DATA   4'd5
`define S_CMD_READ_0    4'd6
`define S_CMD_READ_1    4'd7
`define S_CMD_READ_2    4'd8
`define S_CMD_READ_3    4'd9
`define S_CMD_READ_4    4'd10

module htif ( input  wire        clock

            // from host

            , output reg         rx_ready = 0
            , input  wire        rx_valid
            , input  wire  [7:0] rx_data

            // to bus

            , input  wire        bus_req_ready
            , output reg         bus_req_read    = 0
            , output reg         bus_req_write   = 0
            , output reg  [31:0] bus_req_address = 0
            , output reg  [31:0] bus_req_data

            // from bus

            , input  wire        bus_res_valid
            , input  wire [31:0] bus_res_data

            // to host

            , input  wire        tx_ready
            , output reg         tx_valid        = 0
            , output reg   [7:0] tx_data

            // debug
            , output reg   [3:0] s = `S_START

            );


   reg [31:0] data = 0;
   reg [ 7:0] cmd;

   // fhx, from host transaction
   wire      rx_go = rx_ready & rx_valid;
   wire      tx_go = tx_ready & tx_valid;

   always @(*)
     bus_req_read = s == `S_CMD_RD_DATA && (cmd == "r" || cmd == "R");

   always @(posedge clock) begin
      if (tx_go)
        tx_valid <= 0;
      rx_ready <= 0;
      bus_req_write <= 0;

      case (s)
        `S_START: begin
           rx_ready <= 1;
           if (rx_go) begin
              cmd <= rx_data;
              if (rx_data == "a" || rx_data == "w" || rx_data == "W")
                s <= `S_CMD_AW_ADDR0;
              if (rx_data == "r" || rx_data == "R")
                s <= `S_CMD_RD_DATA;
           end
        end

        `S_CMD_AW_ADDR0: begin
           rx_ready <= 1;
           if (rx_go)
             {data[ 7: 0],s} <= {rx_data,`S_CMD_AW_ADDR1};
        end

        `S_CMD_AW_ADDR1: begin
           rx_ready <= 1;
           if (rx_go)
             {data[15: 8],s} <= {rx_data,`S_CMD_AW_ADDR2};
        end

        `S_CMD_AW_ADDR2: begin
           rx_ready <= 1;
           if (rx_go)
             {data[23:16],s} <= {rx_data,`S_CMD_AW_ADDR3};
        end

        `S_CMD_AW_ADDR3: begin
           rx_ready <= 1;
           if (rx_go) begin
              if (cmd == "a") begin
                 bus_req_address <= {rx_data,data[23:0]};
                 s <= `S_START;
             end else begin
                data[31:24] <= rx_data;
                s           <= `S_CMD_RD_DATA;
             end
           end
        end

        `S_CMD_RD_DATA: begin

           if (cmd == "w" || cmd == "W") begin
              bus_req_data <= data;
              bus_req_write <= 1;
           end

          if (bus_req_ready & (bus_req_write | bus_req_read)) begin
             bus_req_address <= bus_req_address + 4;
             if (cmd == "r" || cmd == "R")
               s <= `S_CMD_READ_0;
             else if (cmd == "W") begin
                cmd <= "w";
                s <= `S_CMD_AW_ADDR0;
             end
             else
               s <= `S_START;
          end
        end

        `S_CMD_READ_0: begin
           if (bus_res_valid) begin
              tx_data  <= bus_res_data[ 7: 0];
              tx_valid <= 1;
              data     <= bus_res_data;
              s        <= `S_CMD_READ_1;
           end
        end

        `S_CMD_READ_1:
          if (tx_go) begin
             tx_data  <= data[15: 8];
             tx_valid <= 1;
             s        <= `S_CMD_READ_2;
          end

        `S_CMD_READ_2:
          if (tx_go) begin
             tx_data  <= data[23:16];
             tx_valid <= 1;
             s        <= `S_CMD_READ_3;
          end

        `S_CMD_READ_3:
          if (tx_go) begin
             tx_data  <= data[31:24];
             tx_valid <= 1;
             s        <= `S_CMD_READ_4;
          end

        `S_CMD_READ_4:
          if (tx_go) begin
             if (cmd == "R") begin
                cmd <= "r";
                s <= `S_CMD_RD_DATA;
             end
             else
               s <= `S_START;
          end
      endcase
   end
endmodule
