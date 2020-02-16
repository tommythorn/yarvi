module top
  (input  wire      clk48,
   output reg [2:0] led = 0,

   input wire       rx,
   output wire      tx);

   reg [2:0]        led_color = 7;
   reg              led_on    = 1;

   //  48e6 + 40% ~= 2^26
   reg [26:0]       clk_div = 0;

   wire             tx_busy;

   reg              tx_data_valid;
   reg  [7:0]       tx_data;

   wire             rx_data_valid;
   wire [7:0]       rx_data;

   rs232out #(115200, 48000000) tx_inst(clk48, tx, tx_data_valid, tx_data_ready, tx_data);
   rs232in  #(115200, 48000000) rx_inst(clk48, rx, rx_data_valid, rx_data);

   reg [7:0]        hello_data;
   reg              hello_data_valid = 0;
   reg [3:0]        hello_p = 0;

   // "Hello World!\r\n" = 48 65 6c 6c 6f 20 57 6f 72 6c 64 21 0d 0a
   always @(posedge clk48)
     case (hello_p)
       0: hello_data <= 'h48;
       1: hello_data <= 'h65;
       2: hello_data <= 'h6c;
       3: hello_data <= 'h6c;
       4: hello_data <= 'h6f;
       5: hello_data <= 'h20;
       6: hello_data <= 'h57;
       7: hello_data <= 'h6f;
       8: hello_data <= 'h72;
       9: hello_data <= 'h6c;
       10: hello_data <= 'h64;
       11: hello_data <= 'h21;
       12: hello_data <= 'h0d;
       13: hello_data <= 'h0a;
       default: hello_data <= 0;
     endcase

   always @(posedge clk48)
     clk_div <= clk_div[26] ? 16000000 - 2 : clk_div - 1; // 3 Hz

   always @(posedge clk48)
     if (clk_div[26]) begin
        led    <= led_on ? ~led_color : ~0;
        led_on <= !led_on;
     end

   always @(*) tx_data = hello_data;

   reg freeze = 0;

   always @(posedge clk48) begin
      tx_data_valid <= !freeze;

      if (tx_data_valid && tx_data_ready)
        hello_p <= hello_p == 13 ? 0 : hello_p + 1;

      if (rx_data_valid)
        freeze <= !freeze;
   end
endmodule
