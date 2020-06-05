CORE=../../rtl/
VERB=
VERB=-DVERBOSE_SIMULATION

TIMEOUT=16000

SRC=../../target/sim/toplevel.v $(CORE)htif.v $(CORE)yarvi_soc.v $(CORE)yarvi_disass.v $(CORE)yarvi.v $(CORE)yarvi_fe.v $(CORE)yarvi_rf.v $(CORE)yarvi_ex.v $(CORE)yarvi_me.v
HDR=$(CORE)riscv.h

CONFIG=-DXMSB=31 -DVMSB=31 -DPMSB=13 -DTIMEOUT=$(TIMEOUT) -DSIMULATION -DDISASSEMBLE $(VERB) -DINIT_MEM=\"$<\"

.PRECIOUS: %.hex %.yarvi

# Adjust to match your RISC-V toolchain
RVPATH=
RVPREFIX=$(RVPATH)riscv64-unknown-elf-
MEMSIZEK=128

all: newtest

TESTSET_UIP= \
  rv32ui-p-add		\
  rv32ui-p-addi		\
  rv32ui-p-and		\
  rv32ui-p-andi		\
  rv32ui-p-auipc	\
  rv32ui-p-beq		\
  rv32ui-p-bge		\
  rv32ui-p-bgeu		\
  rv32ui-p-blt		\
  rv32ui-p-bltu		\
  rv32ui-p-bne		\
  rv32ui-p-fence_i	\
  rv32ui-p-jal		\
  rv32ui-p-jalr		\
  rv32ui-p-lb		\
  rv32ui-p-lbu		\
  rv32ui-p-lh		\
  rv32ui-p-lhu		\
  rv32ui-p-lui		\
  rv32ui-p-lw		\
  rv32ui-p-or		\
  rv32ui-p-ori		\
  rv32ui-p-sb		\
  rv32ui-p-sh		\
  rv32ui-p-simple	\
  rv32ui-p-sll		\
  rv32ui-p-slli		\
  rv32ui-p-slt		\
  rv32ui-p-slti		\
  rv32ui-p-sltiu	\
  rv32ui-p-sltu		\
  rv32ui-p-sra		\
  rv32ui-p-srai		\
  rv32ui-p-srl		\
  rv32ui-p-srli		\
  rv32ui-p-sub		\
  rv32ui-p-sw		\
  rv32ui-p-xor		\
  rv32ui-p-xori

TESTSET_UIV=\
  rv32ui-v-add		\
  rv32ui-v-addi		\
  rv32ui-v-and		\
  rv32ui-v-andi		\
  rv32ui-v-auipc	\
  rv32ui-v-beq		\
  rv32ui-v-bge		\
  rv32ui-v-bgeu		\
  rv32ui-v-blt		\
  rv32ui-v-bltu		\
  rv32ui-v-bne		\
  rv32ui-v-fence_i	\
  rv32ui-v-jal		\
  rv32ui-v-jalr		\
  rv32ui-v-lb		\
  rv32ui-v-lbu		\
  rv32ui-v-ld		\
  rv32ui-v-lh		\
  rv32ui-v-lhu		\
  rv32ui-v-lui		\
  rv32ui-v-lw		\
  rv32ui-v-or		\
  rv32ui-v-ori		\
  rv32ui-v-sb		\
  rv32ui-v-sd		\
  rv32ui-v-sh		\
  rv32ui-v-simple	\
  rv32ui-v-sll		\
  rv32ui-v-slli		\
  rv32ui-v-slt		\
  rv32ui-v-slti		\
  rv32ui-v-sltiu	\
  rv32ui-v-sltu		\
  rv32ui-v-sra		\
  rv32ui-v-srai		\
  rv32ui-v-srl		\
  rv32ui-v-srli		\
  rv32ui-v-sub		\
  rv32ui-v-sw		\
  rv32ui-v-xor		\
  rv32ui-v-xori

TESTSET_MI= \
  rv32mi-p-access	\
  rv32mi-p-breakpoint	\
  rv32mi-p-csr		\
  rv32mi-p-illegal	\
  rv32mi-p-ma_addr	\
  rv32mi-p-ma_fetch	\
  rv32mi-p-mcsr		\
  rv32mi-p-sbreak	\
  rv32mi-p-scall


TESTSET_SI= \
  rv32si-p-csr		\
  rv32si-p-dirty	\
  rv32si-p-ma_fetch	\
  rv32si-p-sbreak	\
  rv32si-p-scall	\
  rv32si-p-wfi

TESTSET_UM= \
  rv32um-p-div		\
  rv32um-p-divu		\
  rv32um-p-mul		\
  rv32um-p-mulh		\
  rv32um-p-mulhsu	\
  rv32um-p-mulhu	\
  rv32um-p-rem		\
  rv32um-p-remu		\
  rv32um-v-div		\
  rv32um-v-divu		\
  rv32um-v-mul		\
  rv32um-v-mulh		\
  rv32um-v-mulhsu	\
  rv32um-v-mulhu	\
  rv32um-v-rem		\
  rv32um-v-remu

TEST_ALL=$(TESTSET_UIP) $(TESTSET_UIV) $(TESTSET_MI) $(TESTSET_SI) $(TESTSET_UA) $(TESTSET_UC) $(TESTSET_UD) $(TESTSET_UF) $(TESTSET_UM)

TESTS=$(TESTSET_UIP)

newtest: $(patsubst %,$(TESTDIR)%.trace,$(TESTS))
	@printf "  Total:   %3d\n" $$(echo $(TESTS) | wc -w)
	@printf "  Passing: %3d\n" $$(ls $(patsubst %,$(TESTDIR)%.trace.pass,$(TESTS)) 2> /dev/null| wc -l)
	@printf "  Failing: %3d\n" $$(ls $(patsubst %,$(TESTDIR)%.trace.fail,$(TESTS)) 2> /dev/null| wc -l)

multisim: $(patsubst %,$(TESTDIR)%.multisim,$(TESTS))

%.multisim: %
	multisim -c $<

%.bin: %
	$(RVPREFIX)objcopy -O binary $^ $@

%.hex: %.bin
	cat $^ /dev/zero|dd iflag=fullblock bs=1k count=$(MEMSIZEK)|hexdump -ve '"%08x\n"' > $@

%.dump: %
	$(RVPREFIX)objdump -d -M numeric,no-aliases $^ > $@

%.spike: %
	spike $< > $@ 2>&1

%.yarvi: %.hex $(SRC) $(HDR)
	iverilog -I$(CORE)/ $(CONFIG) -DTOHOST=$(shell nm $(patsubst %.hex,%,$<) | egrep ' tohost$$' | cut -d' ' -f1) -o $@ $(SRC)

%.trace: %.yarvi %.hex
	./$^ > $@
	if grep -q 'TOHOST =          1' $@;then \
		touch $@.pass; else ln -fs $@ $@.fail; fi

%.run: %.yarvi %.hex
	./$^
