// -----------------------------------------------------------------------
//
// AXI JTAG UART wrapper
//
// ISC License
//
// Copyright (C) 2014 - 2022  Tommy Thorn <tommy-github2@thorn.ws>
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
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
