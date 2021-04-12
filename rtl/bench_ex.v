(* top *)
module top
  (input  wire        clock
  ,input  wire [20:0] td
  ,output reg         tx = 0);

   parameter XMSB  = `XLEN - 1;
   parameter X2MSB = $clog2(`XLEN) - 1;

   reg             insn30 = 0;
   reg  [2:0]      funct3 = 0;
   reg             w = 0;
   reg             fwd1 = 0;
   reg             fwd2 = 0;
   reg             imm1 = 0;
   reg             imm2 = 0;
   reg  [XMSB:0]   imm1val = 0;
   reg  [XMSB:0]   imm2val = 0;

   reg  [X2MSB:0]  rs1, rs2, rd;

   wire [XMSB:0]   result;
   reg  [31:0]     td_r = 0;

   ex #(`XLEN) ex(clock, insn30, funct3, w, fwd1, fwd2, imm1, imm2, imm1val, imm2val, rs1, rs2, rd, result);

   always @(posedge clock) begin
      td_r <= {td_r, td};
      {insn30, funct3, w, fwd1, fwd2, imm1, imm2, rs1, rs2, rd} <= td_r;
      imm1 <= result ^ td_r;
      imm2 <= imm1 ^ result;
      tx <= result;
   end
endmodule
