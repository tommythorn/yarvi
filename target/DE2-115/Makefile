# -----------------------------------------------------------------------
#
#   Copyright 2016,2018,2019,2023,2024 Tommy Thorn - All Rights Reserved
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
#   Bostom MA 02111-1307, USA; either version 2 of the License, or
#   (at your option) any later version; incorporated herein by reference.
#
# -----------------------------------------------------------------------

# This Makefile is based on
# https://github.com/Spritetm/hadbadge2019_fpgasoc/blob/master/blink/Makefile
# and share the same license

PROJ=top
SILENT=@

CORE=../../rtl/
include $(CORE)/Makefile.common
SRC=de2-115.v $(patsubst %,$(CORE)/%,$(YARVISRC))
HDR=$(patsubst %,$(CORE)/%,$(YARVIHDR))

all: program de2-115.sta.rpt

de2-115.map.rpt: $(SRC) Makefile init_mem.0.hex init_mem.1.hex init_mem.2.hex init_mem.3.hex
	quartus_map de2-115

de2-115.fit.rpt: de2-115.map.rpt
	quartus_fit de2-115

de2-115.sta.rpt: de2-115.fit.rpt
	quartus_sta de2-115

de2-115.asm.rpt: de2-115.fit.rpt
	quartus_asm de2-115

program: de2-115.asm.rpt
	quartus_pgm de2-115.cdf

.PRECIOUS: de2-115.map.rpt de2-115.fit.rpt de2-115.sta.rpt de2-115.asm.rpt
