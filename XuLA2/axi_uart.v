`timescale 1ns / 1ps
//**********************************************************************
// The Xess JTAG UART with a AXI-like interface
//**********************************************************************
module axi_uart( input  wire        clk
               , input  wire        reset

               , output wire        tx_ready
               , input  wire        tx_valid
               , input  wire  [7:0] tx_data

               , input  wire        rx_ready
               , output wire        rx_valid
               , output wire  [7:0] rx_data
               );

  wire       rx_empty;
  reg        rx_pop = 0;

  wire       tx_full;
  reg        tx_add = 0;
  reg [7:0]  tx_data_r;

  // Instantiate the communication interface.
  HostIoComm u2(
    .reset_i    (reset),
    .clk_i      (clk),

    .rmv_i      (rx_pop),   // Remove data received from the host.
    .data_o     (rx_data),  // Data from the host.
    .dnEmpty_o  (rx_empty),

    .add_i      (tx_add),   // Add received data to FIFO going back to host
    .data_i     (tx_data_r),  // Data to host.
    .upFull_o   (tx_full)
    );
  defparam u2.SIMPLE_G = 1;

  assign     rx_valid = !rx_empty & !rx_pop;
  assign     tx_ready = !tx_full  & !tx_add;

  always @(posedge clk) begin
    rx_pop <= rx_ready & rx_valid;
    tx_add <= tx_ready & tx_valid;
    tx_data_r <= tx_data;
  end
endmodule
