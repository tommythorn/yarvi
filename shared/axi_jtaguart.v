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
module axi_jtaguart
  ( input  wire        clock
  , input  wire        reset

  , output wire        tx_ready
  , input  wire        tx_valid
  , input  wire  [7:0] tx_data

  , input  wire        rx_ready
  , output wire        rx_valid
  , output wire  [7:0] rx_data
  );

  wire jtaguart_idle_o;

  alt_jtag_atlantic jtag_uart_0_alt_jtag_atlantic
    ( .clk     (clock)
    , .rst_n   (!reset)

    , .r_dat   (tx_data)
    , .r_val   (tx_valid)
    , .r_ena   (tx_ready)

    , .t_dat   (rx_data)
    , .t_dav   (rx_ready)
    , .t_ena   (rx_valid)
    , .t_pause (jtaguart_idle_o)
    );

  defparam jtag_uart_0_alt_jtag_atlantic.INSTANCE_ID = 0,
           jtag_uart_0_alt_jtag_atlantic.LOG2_RXFIFO_DEPTH = 6,
           jtag_uart_0_alt_jtag_atlantic.LOG2_TXFIFO_DEPTH = 6,
           jtag_uart_0_alt_jtag_atlantic.SLD_AUTO_INSTANCE_INDEX = "YES";
endmodule
