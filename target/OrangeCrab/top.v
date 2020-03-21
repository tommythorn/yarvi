module top
  (input  wire      clk48,
   output reg [2:0] led = 0,

   input wire       rx,
   output wire      tx);

   reg [2:0]        led_color = 7;
   reg              led_on    = 1;

   //  48e6 + 40% ~= 2^26
   reg [26:0]       clk_div = 0;

   wire             tx_data_ready;
   wire             tx_data_valid;
   wire [7:0]       tx_data;

   wire             rx_ready; // Ignored, might drop RX data
   wire             rx_data_valid;
   wire [7:0]       rx_data;

   rs232out #(115200, 48000000) tx_inst(clk48, tx, tx_data_valid, tx_data_ready, tx_data);
   rs232in  #(115200, 48000000) rx_inst(clk48, rx, rx_data_valid, rx_data);

   yarvi_soc yarvi_soc
     ( .clock           (clk48)
     , .reset           (0)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)
     );
endmodule
