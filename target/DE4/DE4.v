// -----------------------------------------------------------------------
//
//   Copyright 2016,2019 Tommy Thorn - All Rights Reserved
//
//   This program is free software; you can redistribute it and/or modify
//   it under the terms of the GNU General Public License as published by
//   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
//   Bostom MA 02111-1307, USA; either version 2 of the License, or
//   (at your option) any later version; incorporated herein by reference.
//
// -----------------------------------------------------------------------

`define USE_SERIAL 1

`include "../core/yarvi.h"

module DE4
(
  // Clocks & reset
    input   wire                clock_50MHz_bank2
  , input   wire                cpu_reset_n

  // Serial UART
  , input   wire                uart_rxd
  , output  wire                uart_txd

  // Debug
  , output  reg     [ 7:0]      led

);

   parameter CLOCK_FREQUENCY = 50_000_000;
   wire          clock = clock_50MHz_bank2;
   reg           reset = 0;
//   always @(posedge clock)
//     reset <= ~cpu_reset_n;

   parameter BPS = 115200;

   wire [7:0] tx_data;
   wire       tx_valid;
   wire       tx_ready;
   wire       tx_serial_out;

   wire [7:0] rx_data;
   wire       rx_valid;
   wire       rx_ready;
   wire       rx_overflow;
   wire       rx_serial_in;

`ifdef USE_SERIAL
   rs232tx rs232tx_inst
   ( .clock             (clock)
   , .valid             (tx_valid)
   , .data              (tx_data)
   , .ready             (tx_ready)
   , .serial_out        (tx_serial_out)
   );
   defparam
     rs232tx_inst.frequency = CLOCK_FREQUENCY,
     rs232tx_inst.bps       = BPS;

   rs232rx rs232rx_inst
   ( .clock             (clock)
   , .valid             (rx_valid)
   , .data              (rx_data)
   , .ready             (rx_ready)
   , .overflow          (rx_overflow)
   , .serial_in         (rx_serial_in)
   );
   defparam
     rs232rx_inst.frequency = CLOCK_FREQUENCY,
     rs232rx_inst.bps       = BPS;

   assign rx_serial_in      = uart_rxd;
   assign uart_txd          = tx_serial_out;
`else
   axi_jtaguart axi_jtaguart_inst
     ( .clock           (clock)
     , .reset           (reset)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)
     );
`endif

   wire [3:0] htif_state;
   reg  [1:0] tx_count = 0, rx_count = 0;

   always @(posedge clock) tx_count <= tx_count + (tx_ready & tx_valid);
   always @(posedge clock) rx_count <= rx_count + (rx_ready & rx_valid);

   wire [`VMSB:0] me_pc;

   yarvi_soc yarvi_soc_inst
     ( .clock           (clock)
     , .reset           (reset)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)

     , .htif_state      (htif_state)
     , .me_pc           (me_pc)
     );

   always @(posedge clock)
     led <= me_pc[7:0]; // {htif_state,tx_count,rx_count};
endmodule
