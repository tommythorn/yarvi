`default_nettype none
(* top *)
module top
  (input  wire      clk48,
   output reg [2:0] led = 0,

   input wire       rx,
   output wire      tx);

   wire             tx_data_valid;
   wire             tx_data_ready;
   wire [7:0]       tx_data;

   wire             rx_data_valid;
   wire             rx_data_ready;
   wire [7:0]       rx_data;

   rs232out #(115200, 48000000) tx_inst(clk48, tx, tx_data_valid, tx_data_ready, tx_data);
   rs232in  #(115200, 48000000) rx_inst(clk48, rx, rx_data_valid, rx_data);

   wire [31:0]      me_pc;
   always @(posedge clk48) led <= led + ^me_pc;

   yarvi_soc yarvi_soc
     ( .clock           (clk48)
     , .reset           (0)

     , .rx_ready        (rx_data_ready)
     , .rx_valid        (rx_data_valid)
     , .rx_data         (rx_data)

     , .tx_ready        (tx_data_ready)
     , .tx_valid        (tx_data_valid)
     , .tx_data         (tx_data)

     , .me_pc           (me_pc)
     );

endmodule
