// -----------------------------------------------------------------------
//
//   Copyright 2021 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

This is a silly execution stage without forwarding (WB immediately)

*************************************************************************/

/* The width comparisons in Verilator are completely broken. */
/* verilator lint_off WIDTH */

`default_nettype none

module ex(clock, sub, ashr, funct3, w, fwd1, fwd2, imm1, imm2, imm1val, imm2val,
          rs1, rs2, rd, result);
   parameter XLEN = 64;
   parameter XMSB = XLEN-1;
   parameter X2MSB = $clog2(XLEN) - 1;

   input  wire           clock;
   input  wire           sub;
   input  wire           ashr;
   input  wire [    2:0] funct3;
   input  wire           w;
   input  wire           fwd1;
   input  wire           fwd2;
   input  wire           imm1;
   input  wire           imm2;
   input  wire [XMSB:0]  imm1val;
   input  wire [XMSB:0]  imm2val;
   input  wire [X2MSB:0] rs1, rs2, rd;
   output wire [XMSB:0]  result;

   reg  [XMSB:0]  rf[31:0];

   reg [XMSB:0]  op1;
   reg [XMSB:0]  op2;
   reg [X2MSB:0] rd_r;

   wire [XMSB:0] sum;
   wire          eq;
   wire          lt;
   wire          ltu;

   alu #(XLEN) alu(.sub(sub), .ashr(ashr), .funct3(funct3), .w(w),
                   .op1(1?op1:rf[rs1]), .op2(1?op2:rf[rs2]),
                   .result(result), .sum(sum), .eq(eq), .lt(lt),
                   .ltu(ltu));

   always @(posedge clock) begin
      rd_r <= rd;
      op1 <= fwd1 ? result : imm1 ? imm1val : rf[rs1];
      op2 <= fwd2 ? result : imm2 ? imm2val : rf[rs2];
      rf[rd_r] <= result;
   end

   initial begin
      rf[0] = 0;
      rf[1] = 1;
      rf[2] = 2;
      rf[3] = 3;
      rf[4] = 4;
      rf[5] = 5;
      rf[6] = 6;
      rf[7] = 7;
      rf[8] = 8;
      rf[9] = 9;
      rf[10] = 10;
      rf[11] = 11;
      rf[12] = 12;
      rf[13] = 13;
      rf[14] = 14;
      rf[15] = 15;
      rf[16] = 16;
      rf[17] = 17;
      rf[18] = 18;
      rf[19] = 19;
      rf[20] = 20;
      rf[21] = 21;
      rf[22] = 22;
      rf[23] = 23;
      rf[24] = 24;
      rf[25] = 25;
      rf[26] = 26;
      rf[27] = 27;
      rf[28] = 28;
      rf[29] = 29;
      rf[30] = 30;
      rf[31] = 31;
   end
endmodule
