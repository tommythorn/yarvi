module bemicrocv

  (input         clk_50,
   input  [ 2:0] user_dipsw_n,
   input  [ 1:0] user_button_n,
   output [ 7:0] user_led_n,
   output        gpio1,
   input         gpio2);

   wire          clock = clk_50;

   reg           reset = 1;
   always @(posedge clock)
      reset <= 1'd0;

   wire          serial_out, serial_in;

   assign gpio1     = serial_out;
   assign serial_in = gpio2;

   wire        tx_ready;
   wire        tx_valid;
   wire  [7:0] tx_data;

   wire        rx_ready;
   wire        rx_valid;
   wire  [7:0] rx_data;

   axi_uart axi_uart
     ( .clock           (clock)
     , .reset           (reset)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)
     );

   yarvi_soc yarvi_soc
     ( .clock           (clock)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)
     );

   initial begin
      $dumpfile("test.vcd");
      $dumpvars(0,bemicrocv);
      #1000 $finish;
   end
endmodule
