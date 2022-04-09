CORE=../../rtl/
include $(CORE)/Makefile.common

TIMEOUT=3500000 # Not sure why it doesn't hit the ecall
PMSB=16 # 128 KiB

SRC=../../target/sim/toplevel.v $(patsubst %,$(CORE)/%,$(YARVISRC))
HDR=$(patsubst %,$(CORE)/%,$(YARVIHDR))
DISASS=
CONFIG=$(YARVICONFIG) -DSIMULATION -DTIMEOUT=$(TIMEOUT) $(DISASS) -DINIT_MEM=\"$<\" -DPMSB=$(PMSB) -DKEEP_GOING=1

USE_MYSTDLIB = 0
OBJS = dhry_1.o dhry_2.o stdlib.o
CFLAGS = -MD -O3 -mabi=ilp32 -march=rv32i -DTIME -DRISCV
TOOLCHAIN_PREFIX = /opt/riscv32i/bin/riscv32-unknown-elf-
#EXTRA=-DQUIET
EXTRA=

ifeq ($(USE_MYSTDLIB),1)
CFLAGS += -DUSE_MYSTDLIB -ffreestanding -nostdlib
OBJS += start.o
else
OBJS += syscalls.o
endif

.PRECIOUS: %.hex %.yarvi %.bin

all: dhry.run

trace: dhry.hex $(SRC) $(HDR) Makefile
	$(QUIET)iverilog -I$(CORE)/ $(CONFIG) -DTOHOST=10000000 -DDISASSEMBLE $(EXTRA) -o dhry.tracing $(SRC)
	./dhry.tracing

%.bin: %
	$(QUIET)$(RVPREFIX)objcopy -O binary $^ $@

%.hex: %.bin
	$(QUIET)cat $^ /dev/zero|dd iflag=fullblock bs=1k count=$(MEMSIZEK) 2>/dev/null|hexdump -ve '"%08x\n"' > $@

%.dis: %
	$(RVPREFIX)objdump -d -M numeric,no-aliases $^ > $@

%.spike: %
	spike $< > $@ 2>&1

%.yarvi: %.hex $(SRC) $(HDR) Makefile
	$(QUIET)iverilog -I$(CORE)/ $(CONFIG) -DQUIET=1 -DTOHOST=$(shell nm $(patsubst %.hex,%,$<) | (egrep ' tohost$$' || echo 10000000) | cut -d' ' -f1) -o $@ $(SRC)

%.run: %.yarvi %.hex
	./$^

sim: dhry
	../../../multisim/target/debug/multisim $^

ifeq ($(USE_MYSTDLIB),1)
dhry: $(OBJS) sections.lds
	$(TOOLCHAIN_PREFIX)gcc $(CFLAGS) -Wl,-Bstatic,-T,sections.lds,-Map,dhry.map,--strip-debug -o $@ $(OBJS) -lgcc
	chmod -x $@
else
dhry: $(OBJS)
	$(TOOLCHAIN_PREFIX)gcc $(CFLAGS) -Wl,-Bstatic,-T,riscv.ld,-Map,dhry.map,--strip-debug -o $@ $(OBJS) -lgcc -lc
	chmod -x $@
endif

%.o: %.c
	$(TOOLCHAIN_PREFIX)gcc -c $(CFLAGS) $<

%.o: %.S
	$(TOOLCHAIN_PREFIX)gcc -c $(CFLAGS) $<

dhry_1.o dhry_2.o: CFLAGS += -Wno-implicit-int -Wno-implicit-function-declaration

clean:
	rm -rf *.o *.d dhry.elf dhry.map dhry.bin dhry.hex testbench.vvp testbench.vcd timing.vvp timing.txt testbench_nola.vvp

.PHONY: test clean

-include *.d
