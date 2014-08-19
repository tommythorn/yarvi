#POST= > /dev/null
POST=|sed -e 's/[^m]+m//g' -e 's/  *$$//g'|grep -v '^ *Info'
CC=riscv-gcc
CFLAGS=-std=c99 -m32 -O
IOPTS=

all:
	@echo MAPPING
	quartus_map bemicrocv $(POST)
	@echo FITTING
	@quartus_fit bemicrocv $(POST)
	@echo ASSEMBLING
	@quartus_asm bemicrocv $(POST)
	@echo PROGRAMING
	@quartus_pgm bemicrocv.cdf $(POST)

bemicrocv.sta.summary: bemicrocv.fit.summary
	@echo TIMING ANALYSING
	@quartus_sta bemicrocv $(POST)

SRC=test_yarvi.v bemicrocv.v yarvi.v rs232.v rs232rx.v rs232tx.v

hw.sim: $(SRC) Makefile program.txt mem0.txt mem1.txt mem2.txt mem3.txt
	iverilog -DSIMULATION $(IOPTS) -o /tmp/yarvi $(SRC)
	/tmp/yarvi

hw-unpipeline.sim:
	$(MAKE) hw.sim IOPTS="-DCONFIG_PIPELINE=0 -DCONFIG_FORWARD=0"

hw.riscv hw.riscv.dis: crt0.o hw.o
	riscv-ld -melf32lriscv -o hw.riscv $^
	riscv-objdump -d hw.riscv > hw.riscv.dis

hw.swsim: hw.riscv
	multisim -d $^

hw.swrun: hw.riscv
	multisim $^


term:
	screen /dev/ttyUSB0 115200
