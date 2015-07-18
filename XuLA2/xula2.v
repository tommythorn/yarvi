`timescale 1ns / 1ps
module xula2(input fpgaClk_i);

   wire reset, clk;

   // Generate 50 MHz clock from 12 MHz XuLA clock.
   ClkGen u0(.i(fpgaClk_i), .o(clk));
   defparam u0.CLK_MUL_G = 25;
   defparam u0.CLK_DIV_G =  6;

   // Generate active-high reset.
   ResetGenerator u1(.clk_i(clk), .reset_o(reset));
   defparam u1.PULSE_DURATION_G = 10;

   wire        tx_ready;
   wire        tx_valid;
   wire  [7:0] tx_data;

   wire        rx_ready;
   wire        rx_valid;
   wire  [7:0] rx_data;

  // Instantiate the communication interface.
   axi_uart axi_uart
     ( .clk             (clk)
     , .reset           (reset)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)
     );

   yarvi_soc yarvi_soc
     ( .clk             (clk)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)
     );

endmodule
