// -----------------------------------------------------------------------
//
// Shared YARVI configuration
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

`timescale 1ns/10ps

`define assert(signal) \
   always @(posedge clock) \
     if ((signal) !== 1) begin \
       $display("ASSERTION FAILED in %m: signal de-asserted"); \
       $finish; \
     end

`include "riscv.h"

`define INIT_PC    32'h8000_0000
`define DATA_START 32'h8000_0000
`ifndef INITDIR
`define INITDIR ""
`endif

`ifndef INIT_MEM
`define INIT_MEM "init_mem.hex"
`endif

`ifndef VMSB
`define VMSB 31
`endif

`ifndef XMSB
`define XMSB 31
`endif

`ifndef PMSB
`define PMSB 16
`endif

`ifndef TIMEOUT
`define TIMEOUT 16000
`endif

`define DC_WORDS_LG2 13 // 32 KiB
`define DC_WORDS (1 << `DC_WORDS_LG2)
`define DC_LINE_WORDS_LG2 1 // 2^1 64-bit words = 16 byte line size


// The execution environment really should explicitly provide the configuration,
// definitely XMSB (=XLEN-1), VMSB (=PA-1), and PMSB (=PA-1)
// `define VMSB 31  // Virtual address MSB
// `define PMSB 14  // Physical bits.  We implement 32 KiB = 2^15
// `define XMSB 31  // XLEN-1
