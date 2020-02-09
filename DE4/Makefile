# -----------------------------------------------------------------------
#
#   Copyright 2016,2018,2019 Tommy Thorn - All Rights Reserved
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
COMMON=../core/

all: output_files/DE4.sof_

program: output_files/DE4.sof
	time quartus_pgm DE4.cdf

include $(COMMON)Makefile.common

output_files/DE4.sof_:# DE4.v ../core/yarvi_soc.v ../core/yarvi.v ../core/htif.v ../core/axi_jtaguart.v
	time quartus_map DE4
	time quartus_fit DE4
	time quartus_sta DE4
	grep MHz output_files/DE4.sta.rpt
	time quartus_asm DE4
