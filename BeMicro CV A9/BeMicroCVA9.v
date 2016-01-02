module BeMicroCVA9
(
    // Clocks
    input   wire                CLK_24MHZ        // General Purpose Clock Input, also
                                                 // used by on-board USB Blaster II
  , input   wire                DDR3_CLK_50MHZ   // DDR3 HMC Clock Input

    // User I/O (LED, push buttons, DIP switch)
  , output  reg     [ 7:0]      LEDn             // Green User LEDs
  , input   wire    [ 1:0]      KEYn             // user push buttons
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
);

   wire          clock = DDR3_CLK_50MHZ;
   reg           reset = 1;
   always @(posedge clock)
      reset <= 1'd0;

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

   yarvi_soc yarvi_soc_inst
     ( .clock           (clock)

     , .rx_ready        (rx_ready)
     , .rx_valid        (rx_valid)
     , .rx_data         (rx_data)

     , .tx_ready        (tx_ready)
     , .tx_valid        (tx_valid)
     , .tx_data         (tx_data)
     );
endmodule
