// -----------------------------------------------------------------------
//
//   Copyright 2015 Tommy Thorn - All Rights Reserved
//
//   This program is free software; you can redistribute it and/or modify
//   it under the terms of the GNU General Public License as published by
//   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
//   Bostom MA 02111-1307, USA; either version 2 of the License, or
//   (at your option) any later version; incorporated herein by reference.
//
// -----------------------------------------------------------------------

/* We follow Altera's JTAG UART interface:

  The core has two registers, data (addr 0) and control (addr 1):

   data    (R/W): RAVAIL:16 	   RVALID:1 RSERV:7	     DATA:8
   control (R/W): WSPACE:16 	   RSERV:5 AC:1 WI:1 RI:1    RSERV:6 WE:1 RE:1
*/

`timescale 1ns/10ps

module rs232
   (input  wire        clock,
    output wire        serial_out,
    input  wire        serial_in,

    input  wire        address,
    input  wire        writeenable,
    input  wire [31:0] writedata,
    input  wire        readenable,
    output reg  [31:0] readdata = 32 'h eeee_eeee);

   parameter frequency = 50_000_000;
   parameter bps       =    115_200;

   wire        tx_busy, rx_valid;
   wire [ 7:0] rx_q;

   reg  [ 7:0] pending_data;
   reg         pending_avail = 0;

   rs232rx rs232rx
     ( .clock		(clock)
     , .serial_in	(serial_in)
     , .valid     	(rx_valid)
     , .q		(rx_q));
   defparam
     rs232rx.frequency  = frequency,
     rs232rx.bps        = bps;


   rs232tx rs232tx
      ( .clock		(clock)
      , .serial_out	(serial_out)
      , .d		(writedata[7:0])
      , .we		(address == 0 && writeenable)
      , .busy		(tx_busy));
   defparam
     rs232tx.frequency  = frequency,
     rs232tx.bps        = bps;

`ifdef __ICARUS__
   parameter inputtext  = {`INITDIR,"input.txt"};
   integer   file, ch;
`endif

   always @(posedge clock) begin
      if (readenable)
         case (address)
         0: readdata <= {15'd0, pending_avail, pending_avail, 7'd0, pending_data};
`ifdef __ICARUS__
         1: readdata <= {15'd0,     1'd1, 16'd0};
`else
         1: readdata <= {15'd0, !tx_busy, 16'd0};
`endif
         endcase
      else
         readdata <= 32 'h 6666_6666;

`ifdef __ICARUS__
      if (readenable && address == 0) begin
         if (pending_avail)
            $display("RS232 READ %x '%c'", pending_data, pending_data);

         pending_avail = 0;
         ch = $fgetc(file);
         if (ch >= 0) begin
            pending_avail = 1;
            pending_data = ch;
         end
      end

      if (writeenable && address == 0)
         $display("RS232 WROTE %x '%c'", writedata[7:0], writedata[7:0]);
`else
      if (readenable && address == 0)
         pending_avail <= 0;

      if (rx_valid) begin
        // if (pending_avail) OVERFLOW
        pending_avail <= 1;
        pending_data <= rx_q;
      end
`endif
   end

`ifdef __ICARUS__
   initial begin
      pending_avail = 0;
      file = $fopen(inputtext, "r");
      ch   = $fgetc(file);
      if (ch >= 0) begin
        pending_data = ch;
        pending_avail = 1;
        //$display("RS232 PENDING %x (%c)", pending_data, pending_data);
      end
      // $display("Opening of %s resulted in %d", inputtext, file);
   end
`endif
endmodule
