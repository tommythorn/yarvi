// -----------------------------------------------------------------------
//
// Timing bench for the ALU
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

(* top *)
module top
  (input  wire        clock
  ,input  wire [20:0] td
  ,output reg         tx = 0);

   parameter MSB = `XLEN - 1;

   reg        rd, fwd1, fwd2, rd, sub, ashr;
   reg [2:0]  funct3;
   reg [MSB:0] rs1, rs2;
   reg [MSB:0] op1, op2;
   reg             w;

   reg [20:0] td_r, result_r;
   always @(posedge clock) {fwd1, fwd2, rd, w, sub, ashr, funct3} <= td;

   wire [MSB:0] result;
   wire [MSB:0] sum;
   wire         eq;
   wire         lt;
   wire         ltu;

   alu #(`XLEN) alu(.sub(sub), .ashr(ashr), .funct3(funct3), .w(w),
                    .op1(op1), .op2(op2), .result(result), .sum(sum),
                    .eq(eq), .lt(lt), .ltu(ltu));

`define traditional 1
`ifdef traditional
   always @(posedge clock) begin
      op1 <= fwd1 ? result : rs1;
      op2 <= fwd2 ? result : rs2;
      if (rd)
        rs1 <= result;
      else
        rs2 <= result;

      tx <= rs2[MSB];
   end
`else
   reg [MSB:0]  op1_fwd = 0, op2_fwd = 0;
   always @(*) op1 = op1_fwd | rs1;
   always @(*) op2 = op2_fwd | rs2;
   always @(posedge clock) begin
      op1_fwd <= fwd1 ? result : 0;
      op2_fwd <= fwd2 ? result : 0;
      if (rd)
        rs1 <= result;
      else
        rs2 <= result;

      tx <= rs2[MSB];
   end
`endif
endmodule
