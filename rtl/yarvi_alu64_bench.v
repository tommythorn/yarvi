(* top *)
module top
  (input  wire        clock
  ,input  wire [20:0] td
  ,output reg         tx = 0);

   reg        rd, fwd1, fwd2, rd, insn30;
   reg [2:0]  funct3;
   reg [63:0] rs1, rs2;
   reg [63:0] op1, op2;

   reg [20:0] td_r, result_r;
   always @(posedge clock) {fwd1, fwd2, rd, insn30, funct3} <= td;

   wire [63:0] result;

   yarvi_alu64 alu64(insn30, funct3, op1, op2, result);

`define traditional 1
`ifdef traditional
   always @(posedge clock) begin
      op1 <= fwd1 ? result : rs1;
      op2 <= fwd2 ? result : rs2;
      if (rd)
        rs1 <= result;
      else
        rs2 <= result;

      tx <= rs2[63];
   end
`else
   reg [63:0]  op1_fwd = 0, op2_fwd = 0;
   always @(*) op1 = op1_fwd | rs1;
   always @(*) op2 = op2_fwd | rs2;
   always @(posedge clock) begin
      op1_fwd <= fwd1 ? result : 0;
      op2_fwd <= fwd2 ? result : 0;
      if (rd)
        rs1 <= result;
      else
        rs2 <= result;

      tx <= rs2[63];
   end
`endif
endmodule
