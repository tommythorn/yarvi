// -----------------------------------------------------------------------
//
// Purely combinatorial bypassable RV32 load-alignment and sign-extension
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

// Assumptions:
// - we don't support misaligned loads
// - only RV32

// XXX The bypass feature isn't as useful as expected

/* The width comparisons in Verilator are completely broken. */
/* verilator lint_off WIDTH */

`include "yarvi.h"
`default_nettype none

module yarvi_ld_align
  (input  wire           bypass
  ,input  wire [`XMSB:0] bypass_val
  ,input  wire [    2:0] funct3
  ,input  wire [    1:0] address
  ,input  wire [`XMSB:0] readdata
  ,output reg  [`XMSB:0] aligned);

   reg [31:0] shifted;
   // Conceptually readdata >> (8 * address[1:0]), but optimized
   always @(*) begin
     case (address)
       0: shifted =         readdata;
       1: shifted = {24'hX, readdata[15: 8]}; // must be byte access
       2: shifted = {16'hX, readdata[31:16]}; // at most half access
       3: shifted = {24'hX, readdata[31:24]}; // must be byte access
     endcase

     case (funct3 | {3{bypass}})
       0: aligned = {{24{shifted[ 7]}}, shifted[ 7:0]};//LB
       1: aligned = {{16{shifted[15]}}, shifted[15:0]};//LH
       2: aligned =                     shifted;       //LW
       3: aligned = 'hX;
       4: aligned = { 24'h0,            shifted[ 7:0]};//LBU
       5: aligned = { 16'h0,            shifted[15:0]};//LHU
       6: aligned = 'hX;
       7: aligned = bypass_val;
     endcase
   end
endmodule
