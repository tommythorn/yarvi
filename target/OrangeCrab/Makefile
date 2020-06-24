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

RTL=../../rtl/
SRC=top.v $(RTL)htif.v $(RTL)yarvi_soc.v $(RTL)yarvi.v $(RTL)yarvi_fe.v $(RTL)yarvi_rf.v $(RTL)yarvi_ex.v $(RTL)yarvi_me.v $(RTL)yarvi_alu.v rs232out.v rs232in.v
HDR=$(RTL)riscv.h
CONFIG=-DXMSB=31 -DVMSB=31 -DPMSB=13 -DTIMEOUT=$(TIMEOUT) $(VERB) -DINIT_MEM=\"I-ECALL-01.hex\"

all: $(PROJ).prog

top.json: $(SRC) Makefile
	yosys -p "synth_ecp5 -json $@" $(CONFIG) $(SRC) > yosys.out

%_out.config: %.json
	nextpnr-ecp5 --json $< --lpf $(CONSTR) --textcfg $@ --85k --package CSFBGA285 --speed 6 2> nextpnr-ecp5.out

%.bit: %_out.config
	ecppack --svf-rowsize 100000  --spimode $(FLASH_MODE) --freq $(FLASH_FREQ) \
		--svf $(PROJ).svf --input $< --bit $@

$(PROJ).svf: $(PROJ).bit

#prog: $(PROJ).svf
#	openocd -f ../openocd.cfg -c "init; svf  $<; exit"
%.prog: %.svf
	$(JLINK) $<

clean:
	rm -f $(PROJ).json $(PROJ).svf $(PROJ).bit $(PROJ)_out.config

.PHONY: prog clean
.PRECIOUS: ${PROJ}.json ${PROJ}_out.config

