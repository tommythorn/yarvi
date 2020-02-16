# This Makefile is based on
# https://github.com/Spritetm/hadbadge2019_fpgasoc/blob/master/blink/Makefile
# and share the same license

PROJ=top
CONSTR=OrangeCrab.lpf
TRELLIS=/usr/share/trellis
#Image read mode: qspi, dual-spi, fast-read
FLASH_MODE=qspi
#Image read freq, in MHz: 2.4, 4.8, 9.7, 19.4, 38.8, 62.0
FLASH_FREQ=38.8 #MHz


all: $(PROJ).prog

%.json: %.v rs232out.v rs232in.v
	yosys -p "synth_ecp5 -json $@" $^ > yosys.out

%_out.config: %.json
	nextpnr-ecp5 --json $< --lpf $(CONSTR) --textcfg $@ --85k --package CSFBGA285 --speed 6 2> nextpnr-ecp5.out

%.bit: %_out.config
	ecppack --svf-rowsize 100000  --spimode $(FLASH_MODE) --freq $(FLASH_FREQ) \
		--svf $(PROJ).svf --input $< --bit $@

$(PROJ).svf: $(PROJ).bit

#prog: $(PROJ).svf
#	openocd -f ../openocd.cfg -c "init; svf  $<; exit"
%.prog: %.svf
	JTAGLoadExe $<

clean:
	rm -f $(PROJ).json $(PROJ).svf $(PROJ).bit $(PROJ)_out.config

.PHONY: prog clean
.PRECIOUS: ${PROJ}.json ${PROJ}_out.config

