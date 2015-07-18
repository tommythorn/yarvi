`timescale 1ns / 1ps
module yarvi_soc
            ( input  wire        clk
            , input  wire        reset

            // from host

            , output wire        rx_ready
            , input  wire        rx_valid
            , input  wire  [7:0] rx_data

            // to host

            , input  wire        tx_ready
            , output wire        tx_valid
            , output wire  [7:0] tx_data

            );

   wire        bus_req_ready;
   wire        bus_req_read;
   wire [31:0] bus_req_address;
   wire        bus_req_write;
   wire [31:0] bus_req_data;

   wire        bus_res_valid;
   wire [31:0] bus_res_data;

   htif htif
     ( .clk             (clk)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)

     , .bus_req_ready   (bus_req_ready)
     , .bus_req_read    (bus_req_read)
     , .bus_req_write   (bus_req_write)
     , .bus_req_address (bus_req_address)
     , .bus_req_data    (bus_req_data)

     , .bus_res_valid   (bus_res_valid)
     , .bus_res_data    (bus_res_data)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)
     );

   yarvi yarvi
     ( .clk             (clk)

     , .bus_req_ready   (bus_req_ready)
     , .bus_req_read    (bus_req_read)
     , .bus_req_write   (bus_req_write)
     , .bus_req_address (bus_req_address)
     , .bus_req_data    (bus_req_data)

     , .bus_res_valid   (bus_res_valid)
     , .bus_res_data    (bus_res_data)
     );
endmodule
