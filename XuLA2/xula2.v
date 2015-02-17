`timescale 1ns / 1ps
//**********************************************************************
// This is a simple design for echoing characters received from a host
// back to the host from an FPGA module.
//**********************************************************************
module xula2(input fpgaClk_i);

  wire reset_s, clk_s;

  wire       tx_full;
  reg  [7:0] tx_data;
  wire       tx_write_enable;
  reg        tx_add;

  wire       rx_empty;
  reg        rx_pop = 0;
  wire       rx_data_valid = !rx_empty && !rx_pop;
  wire [7:0] rx_data;

  // Generate 50 MHz clock from 12 MHz XuLA clock.
  ClkGen u0(.i(fpgaClk_i), .o(clk_s));
  defparam u0.CLK_MUL_G = 25;
  defparam u0.CLK_DIV_G =  6;

  // Generate active-high reset.
  ResetGenerator u1(.clk_i(clk_s), .reset_o(reset_s));
  defparam u1.PULSE_DURATION_G = 10;

  wire   [29:0] address;
  wire   [31:0] writedata;
  wire          writeenable;
  reg    [31:0] readdata;
  wire          readenable;
  wire   [ 3:0] byteena;

  // Instantiate the communication interface.
  HostIoComm u2(
    .reset_i    (reset_s),
    .clk_i      (clk_s),

    .rmv_i      (rx_pop),   // Remove data received from the host.
    .data_o     (rx_data),  // Data from the host.
    .dnEmpty_o  (rx_empty),

    .add_i      (tx_add),   // Add received data to FIFO going back to host
    .data_i     (tx_data),  // Data to host.
    .upFull_o   (tx_full)
    );
  defparam u2.SIMPLE_G = 1;

  yarvi yarvi
       ( .clk             (clk_s)
       , .reset           (reset_s)
       , .address         (address)
       , .writeenable     (writeenable)
       , .writedata       (writedata)
       , .byteena         (byteena)
       , .readenable      (readenable)
       , .readdata        (readdata)
       );

  wire rx_read_enable = readenable && address[29] && address[0] == 0 && byteena[0];

  assign tx_write_enable = writeenable && address[29] && address[0] == 0;

  // This process scans the incoming FIFO for characters received from the host.
  // Then it removes a character from the host FIFO and places it in the FIFO that
  // transmits back to the host. It then waits a clock cycle while the FIFO statuses
  // are updated. Then it repeats the process.
  always @(posedge clk_s) begin
    if (readenable)
       case (address[0])
       0: readdata <= {15'd0, rx_data_valid, rx_data_valid, 7'd0, rx_data};
       1: readdata <= {15'd0, !tx_add && !tx_full, 16'd0};
       endcase
    rx_pop <= rx_read_enable && rx_data_valid;

    tx_add <= 0;
    if (!reset_s && !tx_add && !tx_full && tx_write_enable)
    begin
      tx_data <= writedata;
      tx_add  <= 1;    // Places char on FIFO back to host and
                       // delay one cycle so FIFO statuses can update.
    end
  end
endmodule
