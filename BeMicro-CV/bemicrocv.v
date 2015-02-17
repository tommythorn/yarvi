module bemicrocv

  (input         clk_50,
   input  [ 2:0] user_dipsw_n,
   input  [ 1:0] user_button_n,
   output [ 7:0] user_led_n,
   output        gpio1,
   input         gpio2);

   assign        user_led_n = address[7:0];

   wire          tx_busy;

   wire   [ 7:0] rx_q;
   wire          rx_valid;

   wire   [29:0] address;
   wire   [31:0] writedata;
   wire          writeenable;
   wire   [31:0] readdata;
   wire          readenable;
   wire   [ 3:0] byteena;

   reg           reset = 1;
   always @(posedge clk_50)
      reset <= 1'd0;

   wire          serial_out, serial_in;

   assign gpio1 = serial_out;
   assign serial_in = gpio2;

   yarvi yarvi
     ( .clk             (clk_50)
     , .reset           (reset)
     , .address         (address)
     , .writeenable     (writeenable)
     , .writedata       (writedata)
     , .byteena         (byteena)
     , .readenable      (readenable)
     , .readdata        (readdata)
     );

   rs232 rs232
     ( .clk             (clk_50)
     , .serial_out      (serial_out)
     , .serial_in       (serial_in)

     , .address         (address[0])
     , .writeenable     (writeenable & address[29])
     , .writedata       (writedata)
     , .readenable      (readenable  & address[29])
     , .readdata        (readdata));

   reg 		 readdatavalid = 0;
   always @(posedge clk_50)
      readdatavalid <= readenable && address[29];

`ifdef NOTDEF
   always @(posedge clk_50)
      if (writeenable /* && address[29] */)
	$display("IO write %8x/%d -> [%8x]", writedata, byteena, address * 4);

   always @(posedge clk_50)
      if (readenable /* && address[29] */)
	$display("IO read from [%8x]", writedata, byteena, address * 4);

   always @(posedge clk_50)
      if (readdatavalid)
	$display("IO read -> %8x", readdata);
`endif
endmodule
