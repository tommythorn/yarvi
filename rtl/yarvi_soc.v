// -----------------------------------------------------------------------
//
// Dummy wrapper for the YARVI core
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

`include "yarvi.h"
`default_nettype none
`timescale 1ns / 1ps
module yarvi_soc
  ( input  wire        clock
  , input  wire        reset

  // from host

  , output wire        rx_ready
/* verilator lint_off UNUSED */
  , input  wire        rx_valid
  , input  wire  [7:0] rx_data

  // to host

  , input  wire        tx_ready
  , output wire        tx_valid
  , output wire  [7:0] tx_data
/* verilator lint_on UNUSED */

  // debug
  , output wire [`VMSB:0] debug);

   assign rx_ready = 1;
   assign {tx_valid, tx_data} = debug[8:0];

   yarvi yarvi
     ( .clock           (clock)
     , .reset           (reset)

/* verilator lint_off PINCONNECTEMPTY */
     , .retire_valid    ()
     , .retire_priv     ()
     , .retire_pc       ()
     , .retire_insn     ()
     , .retire_rd       ()
     , .retire_wb_val   ()
     , .debug           (debug)
     );
endmodule
