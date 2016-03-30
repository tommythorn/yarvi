`timescale 1ns / 1ps
module axi_uart
  ( input  wire        clock
  , input  wire        reset

  , input  wire        serial_in
  , output wire        serial_out

  , output wire        tx_ready
  , input  wire        tx_valid
  , input  wire  [7:0] tx_data

  , input  wire        rx_ready
  , output reg         rx_valid = 0
  , output reg   [7:0] rx_data = 'h XX
  );

   parameter frequency = 50_000_000;
   parameter bps       =    115_200;

   /* Very minimal one-byte buffer */

`ifdef __ICARUS__
   assign      tx_ready = 1;
`else
   assign      tx_ready = !rs232tx_busy;
`endif

   wire        rs232tx_busy;
   wire        rs232rx_valid;
   wire [ 7:0] rs232rx_q;

   rs232rx rs232rx
     ( .clock		(clock)
     , .serial_in	(serial_in)
     , .valid     	(rs232rx_valid)
     , .q		(rs232rx_q));
   defparam
     rs232rx.frequency  = frequency,
     rs232rx.bps        = bps;

   rs232tx rs232tx
      ( .clock		(clock)
      , .serial_out	(serial_out)
      , .d		(tx_data)
      , .we		(tx_valid & tx_ready)
      , .busy		(rs232tx_busy));
   defparam
     rs232tx.frequency  = frequency,
     rs232tx.bps        = bps;

   parameter inputtext  = {`INITDIR,"input.txt"};
   integer   file, ch;

   always @(posedge clock) begin
      if (rx_ready & rx_valid) begin
         rx_valid <= 0;

`ifdef __ICARUS__
         $display("RS232 READ %x '%c'", rx_data, rx_data);
         ch = $fgetc(file);
         if (ch >= 0) begin
            rx_valid <= 1;
            rx_data <= ch;
         end
`endif
      end

      if (rs232rx_valid) begin
         rx_valid <= 1;
         rx_data <= rs232rx_q;
      end
   end

`ifdef __ICARUS__
   always @(posedge clock)
      if (tx_ready & tx_valid)
         $display("RS232 WROTE %x '%c'", tx_data, tx_data);

   initial begin
      file = $fopen(inputtext, "r");
      #100
      rx_valid = 1;
   end
`endif
endmodule
