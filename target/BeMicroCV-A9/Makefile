# -----------------------------------------------------------------------
#
#   Copyright 2016,2018,2022 Tommy Thorn - All Rights Reserved
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
#   Bostom MA 02111-1307, USA; either version 2 of the License, or
#   (at your option) any later version; incorporated herein by reference.
#
# -----------------------------------------------------------------------

TESTDIR=
PROGRAM=demo
CORE=../../rtl
include $(CORE)/Makefile.common
SRC=$(patsubst %,$(CORE)/%,$(YARVISRC))

program: output_files/BeMicroCVA9.sof
	time quartus_pgm BeMicroCVA9.cdf

output_files/BeMicroCVA9.sof: BeMicroCVA9.v $(SRC)
	time quartus_map BeMicroCVA9
	time quartus_fit BeMicroCVA9
	time quartus_asm BeMicroCVA9
	time quartus_sta BeMicroCVA9
	grep MHz output_files/BeMicroCVA9.sta.rpt
