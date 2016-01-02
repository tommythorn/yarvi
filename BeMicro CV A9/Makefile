program: output_files/BeMicroCVA9.sof
	quartus_pgm BeMicroCVA9.cdf

output_files/BeMicroCVA9.sof: BeMicroCVA9.v ../shared/yarvi_soc.v ../shared/yarvi.v ../shared/htif.v axi_jtaguart.v
	quartus_map BeMicroCVA9
	quartus_fit BeMicroCVA9
	quartus_asm BeMicroCVA9
	quartus_sta BeMicroCVA9
