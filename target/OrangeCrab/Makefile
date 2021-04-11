# This Makefile is based on
# https://github.com/Spritetm/hadbadge2019_fpgasoc/blob/master/blink/Makefile
# and share the same license

PROJ=top
CONSTR=OrangeCrab.lpf
#Image read mode: qspi, dual-spi, fast-read
FLASH_MODE=qspi
#Image read freq, in MHz: 2.4, 4.8, 9.7, 19.4, 38.8, 62.0
FLASH_FREQ=38.8 #MHz
JLINK=JTAGLoadExe
#JLINK=JTAGLoad
SILENT=@

CORE=../../rtl/
include $(CORE)/Makefile.common
SRC=top.v $(patsubst %,$(CORE)/%,$(YARVISRC)) rs232out.v rs232in.v
HDR=$(patsubst %,$(CORE)/%,$(YARVIHDR))
CONFIG=$(YARVICONFIG) -DINIT_MEM=\"I-ECALL-01.hex\"

OPTS=abc2 abc9 abc9_nowidelut
#OPTS=abc9_noflatten # this option didn't work for me

all: $(patsubst %,%.config,$(OPTS))

%.json: $(SRC) Makefile
	$(SILENT)yosys -p "synth_ecp5 -$(shell echo $(basename $@)|sed 's/_/ -/g') -json $@" $(CONFIG) $(SRC) > $@.yosys.out

%.config: %.json
	$(SILENT)-nextpnr-ecp5 --json $< --lpf $(CONSTR) --textcfg $@ --85k --package CSFBGA285 --speed 6 2> $@.out
	$(SILENT)egrep -Ho ': [0-9\.]+ MHz' $@.out | tail -1
%.bit: %.config
	ecppack --svf-rowsize 100000  --spimode $(FLASH_MODE) --freq $(FLASH_FREQ) \
		--svf $(PROJ).svf --input $< --bit $@

$(PROJ).svf: $(PROJ).bit

#prog: $(PROJ).svf
#	openocd -f ../openocd.cfg -c "init; svf  $<; exit"
%.prog: %.svf
	$(JLINK) $<

clean:
	rm -f $(PROJ).json $(PROJ).svf $(PROJ).bit $(PROJ).config

.PHONY: prog clean
.PRECIOUS: ${PROJ}.json ${PROJ}.config

