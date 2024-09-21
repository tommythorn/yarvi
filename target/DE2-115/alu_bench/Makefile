# why I need sudo here?
#program: de2-115.sof
#	sudo quartus_pgm de2-115.cdf

de2-115.sof: bench_alu.v
	quartus_map de2-115
	quartus_fit de2-115
	quartus_asm de2-115
	quartus_sta de2-115
