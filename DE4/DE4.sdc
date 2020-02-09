create_clock -name CLK_M2 -period "600 MHZ" [get_ports clock_50MHz_bank2]
#create_clock -name CLK_M3 -period "50 MHZ" [get_ports clock_50MHz_bank3]
#create_clock -name CLK_M4 -period "50 MHZ" [get_ports clock_50MHz_bank4]
#create_clock -name CLK_M5 -period "50 MHZ" [get_ports clock_50MHz_bank5]
#create_clock -name CLK_M6 -period "50 MHZ" [get_ports clock_50MHz_bank6]
#create_clock -name CLK_M7 -period "50 MHZ" [get_ports clock_50MHz_bank7]
derive_pll_clocks
derive_clock_uncertainty
