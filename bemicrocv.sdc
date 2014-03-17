create_clock -name "clk_50" -period 20.000ns [get_ports {clk_50}]
create_clock -name "clk_24" -period 41.667ns [get_ports {clk_24}]

# Automatically constrain PLL and other generated clocks
derive_pll_clocks -create_base_clocks

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty
