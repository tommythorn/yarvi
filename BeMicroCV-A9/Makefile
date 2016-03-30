# -----------------------------------------------------------------------
#
#   Copyright 2016 Tommy Thorn - All Rights Reserved
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
#   Bostom MA 02111-1307, USA; either version 2 of the License, or
#   (at your option) any later version; incorporated herein by reference.
#
# -----------------------------------------------------------------------

# You might not need this, I did.
export LD_LIBRARY_PATH:=/lib:/usr/lib:$(QUARTUS_BINDIR)
export PATH:=$(PATH):$(QUARTUS_BINDIR):$(QUARTUS_BINDIR)/../adm

TESTDIR=
PROGRAM=demo
COMMON=../shared/

program: output_files/BeMicroCVA9.sof
	time quartus_pgm BeMicroCVA9.cdf

timing: output_files/BeMicroCVA9.sof
	quartus_sta BeMicroCVA9

include $(COMMON)Makefile.common

output_files/BeMicroCVA9.sof: demo.riscv.txt BeMicroCVA9.v ../shared/yarvi_soc.v ../shared/yarvi.v ../shared/htif.v ../shared/axi_jtaguart.v
	time quartus_map BeMicroCVA9
	time quartus_fit BeMicroCVA9
	time quartus_asm BeMicroCVA9
