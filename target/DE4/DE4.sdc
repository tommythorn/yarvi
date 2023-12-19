create_clock -name clock_50MHz_bank2 -period "200 MHZ" [get_ports clock_50MHz_bank2]
#create_clock -name clock_50MHz_bank3 -period "50 MHZ" [get_ports clock_50MHz_bank3]
#create_clock -name clock_50MHz_bank4 -period "50 MHZ" [get_ports clock_50MHz_bank4]
#create_clock -name clock_50MHz_bank5 -period "50 MHZ" [get_ports clock_50MHz_bank5]
#create_clock -name clock_50MHz_bank6 -period "50 MHZ" [get_ports clock_50MHz_bank6]
#create_clock -name clock_50MHz_bank7 -period "50 MHZ" [get_ports clock_50MHz_bank7]
derive_pll_clocks
derive_clock_uncertainty
