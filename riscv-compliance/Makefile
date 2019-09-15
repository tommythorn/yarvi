CORE=../core/

VERB=
VERB=-DVERBOSE_SIMULATION

ICARUS_SRC=../sim/toplevel.v $(CORE)htif.v $(CORE)yarvi_soc.v
SRC=$(CORE)yarvi.v $(CORE)yarvi_fe.v $(CORE)yarvi_rf.v $(CORE)yarvi_ex.v $(CORE)yarvi_me.v $(CORE)yarvi_disass.v
HDR=$(CORE)riscv.h

# Adjust to match your RISC-V toolchain
RVPATH=
RVPREFIX=$(RVPATH)riscv32-unknown-elf-
MEMSIZEK=32

.PRECIOUS: %.hex

TESTS= \
  I-ADD-01.elf \
  I-ADDI-01.elf \
  I-AND-01.elf \
  I-ANDI-01.elf \
  I-AUIPC-01.elf \
  I-BEQ-01.elf \
  I-BGE-01.elf \
  I-BGEU-01.elf \
  I-BLT-01.elf \
  I-BLTU-01.elf \
  I-BNE-01.elf \
  I-CSRRC-01.elf \
  I-CSRRCI-01.elf \
  I-CSRRS-01.elf \
  I-CSRRSI-01.elf \
  I-CSRRW-01.elf \
  I-CSRRWI-01.elf \
  I-DELAY_SLOTS-01.elf \
  I-EBREAK-01.elf \
  I-ECALL-01.elf \
  I-ENDIANESS-01.elf \
  I-FENCE.I-01.elf \
  I-IO.elf \
  I-JAL-01.elf \
  I-JALR-01.elf \
  I-LB-01.elf \
  I-LBU-01.elf \
  I-LH-01.elf \
  I-LHU-01.elf \
  I-LUI-01.elf \
  I-LW-01.elf \
  I-MISALIGN_JMP-01.elf \
  I-MISALIGN_LDST-01.elf \
  I-NOP-01.elf \
  I-OR-01.elf \
  I-ORI-01.elf \
  I-RF_size-01.elf \
  I-RF_width-01.elf \
  I-RF_x0-01.elf \
  I-SB-01.elf \
  I-SH-01.elf \
  I-SLL-01.elf \
  I-SLLI-01.elf \
  I-SLT-01.elf \
  I-SLTI-01.elf \
  I-SLTIU-01.elf \
  I-SLTU-01.elf \
  I-SRA-01.elf \
  I-SRAI-01.elf \
  I-SRL-01.elf \
  I-SRLI-01.elf \
  I-SUB-01.elf \
  I-SW-01.elf \
  I-XOR-01.elf \
  I-XORI-01.elf


compliance: $(patsubst %.elf,%.comply,$(TESTS))

newtest: $(patsubst %,$(TESTDIR)%.trace,$(TESTS))
	@printf "  Total:   %3d\n" $$(echo $(TESTS) | wc -w)
	@printf "  Passing: %3d\n" $$(ls $(patsubst %,$(TESTDIR)%.trace.pass,$(TESTS)) 2> /dev/null| wc -l)
	@printf "  Failing: %3d\n" $$(ls $(patsubst %,$(TESTDIR)%.trace.fail,$(TESTS)) 2> /dev/null| wc -l)

%.bin: %.elf
	$(RVPREFIX)objcopy -O binary $^ $@

%.hex: %.bin
	cat $^ /dev/zero|dd iflag=fullblock bs=1k count=$(MEMSIZEK)|hexdump -ve '"%08x\n"' > $@

%.dump: %
	riscv32-unknown-elf-objdump -d -M numeric,no-aliases $^ > $@

%.spike: %
	spike $< > $@ 2>&1

%.yarvi: %.hex $(ICARUS_SRC) $(SRC) $(HDR)
	iverilog \
		-DBEGIN_SIGNATURE=`nm $(basename $<).elf|egrep ' begin_signature$$'|cut -d' ' -f1` \
		-DEND_SIGNATURE=`nm $(basename $<).elf|egrep ' end_signature$$'|cut -d' ' -f1` \
		-DTOHOST=`nm $(basename $<).elf|egrep ' tohost$$'|cut -d' ' -f1` \
		 -I../core/ -DSIMULATION $(VERB) -DINIT_MEM=\"$<\" \
		-o $@ $(ICARUS_SRC) $(SRC)

%.vsim: %.hex $(SRC) $(HDR) sim_main.cpp
	verilator -CFLAGS -O3 -O3 -Wall --cc --exe sim_main.cpp \
		--top-module yarvi \
		-DBEGIN_SIGNATURE=`nm $(basename $<).elf|egrep ' begin_signature$$'|cut -d' ' -f1` \
		-DEND_SIGNATURE=`nm $(basename $<).elf|egrep ' end_signature$$'|cut -d' ' -f1` \
		-DTOHOST=`nm $(basename $<).elf|egrep ' tohost$$'|cut -d' ' -f1` \
		$(UNDEFS) \
		 -I../core/ -DSIMULATION $(VERB) -DINIT_MEM=\"$<\" \
		-Mdir $@ $(SRC)
	make -C $@ -f Vyarvi.mk Vyarvi
	$@/Vyarvi

%.trace: %.yarvi
	./$^ > $@
	if grep -q 'TOHOST 00000001' $@;then \
		touch $@.pass; else ln -fs $@ $@.fail; fi

%.run: %.yarvi
	./$^

%.comply: %.yarvi
	./$^ | grep ^Signature -A999999|tail -n +2 | \
		if diff - ../../riscv-compliance/riscv-test-suite/rv32i/references/$(basename $<).reference_output; then \
			touch $@.pass; else touch $@.fail; fi

