# -----------------------------------------------------------------------
#
#   Copyright 2016,2018,2019,2023 Tommy Thorn - All Rights Reserved
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
SRC=DE4.v $(patsubst %,$(CORE)/%,$(YARVISRC))
HDR=$(patsubst %,$(CORE)/%,$(YARVIHDR))

all: program DE4.sta.rpt

DE4.map.rpt: $(SRC) Makefile init_mem.0.hex init_mem.1.hex init_mem.2.hex init_mem.3.hex
	quartus9.1sp2_map DE4

DE4.fit.rpt: DE4.map.rpt
	quartus9.1sp2_fit DE4

DE4.sta.rpt: DE4.fit.rpt
	quartus9.1sp2_sta DE4

DE4.asm.rpt: DE4.fit.rpt
	quartus9.1sp2_asm DE4

program: DE4.asm.rpt
	quartus_pgm DE4.cdf

.PRECIOUS: DE4.map.rpt DE4.fit.rpt DE4.sta.rpt DE4.asm.rpt
