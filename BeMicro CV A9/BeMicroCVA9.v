// -----------------------------------------------------------------------
//
//   Copyright 2016 Tommy Thorn - All Rights Reserved
//
//   This program is free software; you can redistribute it and/or modify
//   it under the terms of the GNU General Public License as published by
//   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
//   Bostom MA 02111-1307, USA; either version 2 of the License, or
//   (at your option) any later version; incorporated herein by reference.
//
// -----------------------------------------------------------------------

module BeMicroCVA9
(
    // Clocks
    input   wire                CLK_24MHZ        // General Purpose Clock Input, also
                                                 // used by on-board USB Blaster II
  , input   wire                DDR3_CLK_50MHZ   // DDR3 HMC Clock Input

    // User I/O (LED, push buttons, DIP switch)
  , output  wire    [ 7:0]      USER_LED         // Green User LEDs
  , input   wire    [ 1:0]      TACT             // user push buttons
  , input   wire    [ 3:0]      DIP_SW           // user DIP switch

`ifdef eeprom
    // I2C EEPROM interface
  , inout   wire                EEPROM_SDA       // serial data/address
  , output  wire                EEPROM_SCL       // serial clock
`endif

`ifdef sdcard
    // micro SD card interface
  , output  wire                SDCLK            // SD clock
  , output  wire                SDCMD            // SD command line
  , inout   wire    [ 3:0]      SDD              // SD data
`endif

`ifdef ddr3
    // DDR3 interface
  , input   wire                DDR3_OCT_RZQIN   // external 100 ohm RZQ resistor connected to this pin (B11)
  , output  wire    [12:0]      DDR3_A           // address bus
  , output  wire    [ 2:0]      DDR3_BA          // bank address bus
  , output  wire                DDR3_CASn        // column address strobe
  , output  wire                DDR3_CLK_P       // clock(p) output to DDR3 memory
  , output  wire                DDR3_CLK_N       // clock(n) output to DDR3 memory
  , output  wire                DDR3_CKE         // clock enable
  , output  wire                DDR3_CSn         // chip select
  , output  wire    [ 1:0]      DDR3_DM          // data mask
  , inout   wire    [15:0]      DDR3_DQ          // data bus (15:8 = lane 1; 7:0 = lane 0)
  , inout   wire    [ 1:0]      DDR3_DQS_P       // data strobe(p)
  , inout   wire    [ 1:0]      DDR3_DQS_N       // data strobe(n)
  , output  wire                DDR3_ODT         // on die termination control
  , output  wire                DDR3_RASn        // row address strobe
  , output  wire                DDR3_RESETn      // reset output to DDR3 memory
  , output  wire                DDR3_WEn         // write enable to DDR3 memory
`endif

`ifdef ethernet
    // Ethernet interface
  , input   wire                ENET_RX_CLK      // RGMII RX Clock Output from PHY
  , output  wire                ENET_GTX_CLK     // RGMII TX Ref Clock Input to PHY
  , output  wire                ENET_RSTn        // Reset Input to PHY
  , input   wire                ENET_INTn        // Interrupt Output from PHY
  , output  wire                ENET_TX_EN       // RGMII TX Control Input to PHY
  , input   wire                ENET_RX_DV       // RGMII RX Control Output from PHY
  , output  wire                ENET_MDC         // Management Data Clock Input to PHY
  , inout   wire                ENET_MDIO        // Management Data I/O
  , output  wire    [ 3:0]      ENET_TXD         // RGMII TX Data Input to PHY
  , input   wire    [ 3:0]      ENET_RXD         // RGMII RX Data Output from PHY
`endif


  , input   wire                GPIO2            // J1.2
  , output  wire                GPIO3            // J1.3
  , output  wire                GPIO4            // J1.4
  , output  wire                GPIO5            // J1.5
  , output  wire                GPIO6            // J1.6
  , output  wire                GPIO7            // J1.7
  , output  wire                GPIO8            // J1.8
  , output  wire                GPIO1            // J1.9
  , output  wire                GPIO_D           // J1.10

  , output  wire                DIFF_TX_P9       // J1.13
  , input   wire                DIFF_TX_N9       // J1.14
  , output  wire                LVDS_TX_O_N3     // J1.15
  );

   parameter CLOCK_FREQUENCY = 50_000_000;
   wire          clock = DDR3_CLK_50MHZ; //CLK_24MHZ;
   reg           reset = 1; always @(posedge clock) reset <= 0;

   parameter BPS = 115200;

   reg [7:0] leds;

   // mirror the LEDs so they make sense when facing the Ethernet port
   assign {USER_LED[0],USER_LED[1],USER_LED[2],USER_LED[3],
           USER_LED[4],USER_LED[5],USER_LED[6],USER_LED[7]} = ~leds;

   wire [7:0] tx_data;
   wire       tx_valid;
   wire       tx_ready;
   wire       tx_serial_out = DIFF_TX_P9;

   wire [7:0] rx_data;
   wire       rx_valid;
   wire       rx_ready;
   wire       rx_overflow;
   wire       rx_serial_in;

`ifdef USE_SERIAL
   rs232tx rs232tx_inst
   ( .clock             (clock)
   , .valid             (tx_valid)
   , .data              (tx_data)
   , .ready             (tx_ready)
   , .serial_out        (tx_serial_out)
   );
   defparam
     rs232tx_inst.frequency = CLOCK_FREQUENCY,
     rs232tx_inst.bps       = BPS;

   rs232rx rs232rx_inst
   ( .clock             (clock)
   , .valid             (rx_valid)
   , .data              (rx_data)
   , .ready             (rx_ready)
   , .overflow          (rx_overflow)
   , .serial_in         (rx_serial_in)
   );
   defparam
     rs232rx_inst.frequency = CLOCK_FREQUENCY,
     rs232rx_inst.bps       = BPS;

   assign rx_serial_in      = DIFF_TX_N9;
   assign DIFF_TX_P9        = tx_serial_out;
`else
   axi_jtaguart axi_jtaguart_inst
     ( .clock           (clock)
     , .reset           (reset)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)
     );
`endif

   wire [3:0] htif_state;
   reg  [1:0] tx_count = 0, rx_count = 0;

   always @(posedge clock) tx_count <= tx_count + (tx_ready & tx_valid);
   always @(posedge clock) rx_count <= rx_count + (rx_ready & rx_valid);

   yarvi_soc yarvi_soc_inst
     ( .clock           (clock)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)

     , .htif_state      (htif_state)
     );

   always @(posedge clock)
     leds <= {htif_state,tx_count,rx_count};
endmodule
