CORE=../core/
VERB=
VERB=-DVERBOSE_SIMULATION

TIMEOUT=16000

SRC=../sim/toplevel.v $(CORE)htif.v $(CORE)yarvi_soc.v $(CORE)yarvi_disass.v $(CORE)yarvi.v $(CORE)yarvi_fe.v $(CORE)yarvi_rf.v $(CORE)yarvi_ex.v $(CORE)yarvi_me.v
HDR=$(CORE)riscv.h

CONFIG=-DXMSB=31 -DVMSB=31 -DPMSB=13 -DTIMEOUT=$(TIMEOUT) -DSIMULATION -DDISASSEMBLE $(VERB) -DINIT_MEM=\"$<\"

.PRECIOUS: %.hex %.yarvi

# Adjust to match your RISC-V toolchain
RVPATH=
RVPREFIX=$(RVPATH)riscv64-unknown-elf-
MEMSIZEK=128

multisim: $(patsubst %,$(TESTDIR)%.multisim,$(TESTS))

%.multisim: %
	multisim -c $<

%.elf: %.c
	$(RVPREFIX)gcc -O $^ -o $@

%.bin: %.elf
	$(RVPREFIX)objcopy -O binary $^ $@

%.hex: %.bin
	cat $^ /dev/zero|dd iflag=fullblock bs=1k count=$(MEMSIZEK)|hexdump -ve '"%08x\n"' > $@

%.dump: %
	riscv32-unknown-elf-objdump -d -M numeric,no-aliases $^ > $@

%.spike: %
	spike $< > $@ 2>&1

%.yarvi: %.hex $(SRC) $(HDR)
	iverilog -I../core/ $(CONFIG) -DTOHOST=$(shell nm $(patsubst %.hex,%,$<) | egrep ' tohost$$' | cut -d' ' -f1) -o $@ $(SRC)

%.trace: %.yarvi %.hex
	./$^ > $@
	if grep -q 'TOHOST =          1' $@;then \
		touch $@.pass; else ln -fs $@ $@.fail; fi

%.run: %.yarvi %.hex
	./$^


hello_world.elf: hello_world.c
	$(RVPREFIX)gcc -O -march=rv32im -mabi=ilp32 hello_world.c -o hello_world.elf

hello_world.dis: hello_world.elf
	$(RVPREFIX)objdump -d hello_world.elf
