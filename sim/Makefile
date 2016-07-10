# Program Under Test, PUT
TESTDIR=/opt/rv32/riscv32-unknown-elf/share/riscv-tests/isa/
PUT=$(TESTDIR)rv32ui-p-fence_i
OUTDIR=/tmp/

COMMON=../shared/

VERB=
VERB=-DVERBOSE_SIMULATION #-DSIMULATION_VERBOSE_PIPELINE

SRC=toplevel.v $(COMMON)htif.v $(COMMON)yarvi_soc.v $(COMMON)yarvi.v

all: test1

include $(COMMON)Makefile.common

TEST_BASIC= \
  rv32ui-p-add \
  rv32ui-p-addi \
  rv32ui-p-and \
  rv32ui-p-andi \
  rv32ui-p-auipc \
  rv32ui-p-beq \
  rv32ui-p-bge \
  rv32ui-p-bgeu \
  rv32ui-p-blt \
  rv32ui-p-bltu \
  rv32ui-p-bne \
  rv32ui-p-fence_i \
  rv32ui-p-j \
  rv32ui-p-jal \
  rv32ui-p-jalr \
  rv32ui-p-lb \
  rv32ui-p-lbu \
  rv32ui-p-lh \
  rv32ui-p-lhu \
  rv32ui-p-lui \
  rv32ui-p-lw \
  rv32ui-p-or \
  rv32ui-p-ori \
  rv32ui-p-sb \
  rv32ui-p-sh \
  rv32ui-p-simple \
  rv32ui-p-sll \
  rv32ui-p-slli \
  rv32ui-p-slt \
  rv32ui-p-slti \
  rv32ui-p-sra \
  rv32ui-p-srai \
  rv32ui-p-srl \
  rv32ui-p-srli \
  rv32ui-p-sub \
  rv32ui-p-sw \
  rv32ui-pt-add \
  rv32ui-pt-addi \
  rv32ui-pt-and \
  rv32ui-pt-andi \
  rv32ui-pt-auipc \
  rv32ui-pt-beq \
  rv32ui-pt-bge \
  rv32ui-pt-bgeu \
  rv32ui-pt-blt \
  rv32ui-pt-bltu \
  rv32ui-pt-bne \
  rv32ui-pt-fence_i \
  rv32ui-pt-j \
  rv32ui-pt-jal \
  rv32ui-pt-jalr \
  rv32ui-pt-lb \
  rv32ui-pt-lbu \
  rv32ui-pt-lh \
  rv32ui-pt-lhu \
  rv32ui-pt-lui \
  rv32ui-pt-lw \
  rv32ui-pt-or \
  rv32ui-pt-ori \
  rv32ui-pt-sb \
  rv32ui-pt-sh \
  rv32ui-pt-simple \
  rv32ui-pt-sll \
  rv32ui-pt-slli \
  rv32ui-pt-slt \
  rv32ui-pt-slti \
  rv32ui-pt-sra \
  rv32ui-pt-srai \
  rv32ui-pt-srl \
  rv32ui-pt-srli \
  rv32ui-pt-sub \
  rv32ui-pt-sw \
  rv32ui-pt-xor \
  rv32ui-pt-xori \
  rv32ui-p-xor \
  rv32ui-p-xori

TEST_ATOMIC= \
  rv32ui-p-amoadd_w \
  rv32ui-p-amoand_w \
  rv32ui-p-amomaxu_w \
  rv32ui-p-amomax_w \
  rv32ui-p-amominu_w \
  rv32ui-p-amomin_w \
  rv32ui-p-amoor_w \
  rv32ui-p-amoswap_w \
  rv32ui-pt-amoadd_w \
  rv32ui-pt-amoand_w \
  rv32ui-pt-amomaxu_w \
  rv32ui-pt-amomax_w \
  rv32ui-pt-amominu_w \
  rv32ui-pt-amomin_w \
  rv32ui-pt-amoor_w \
  rv32ui-pt-amoswap_w \
  rv32ui-pm-lrsc

TEST_MULDIV= \
  rv32ui-p-div \
  rv32ui-p-divu \
  rv32ui-p-mul \
  rv32ui-p-mulh \
  rv32ui-p-mulhsu \
  rv32ui-p-mulhu \
  rv32ui-p-rem \
  rv32ui-p-remu \
  rv32ui-pt-div \
  rv32ui-pt-divu \
  rv32ui-pt-mul \
  rv32ui-pt-mulh \
  rv32ui-pt-mulhsu \
  rv32ui-pt-mulhu \
  rv32ui-pt-rem \
  rv32ui-pt-remu

TEST_SUPERVISOR= \
  rv32mi-p-csr \
  rv32mi-p-illegal \
  rv32mi-p-ma_addr \
  rv32mi-p-ma_fetch \
  rv32mi-pm-ipi \
  rv32mi-p-sbreak \
  rv32mi-p-scall \
  rv32mi-p-timer \
  rv32si-p-csr \
  rv32si-p-illegal \
  rv32si-p-ma_addr \
  rv32si-p-ma_fetch \
  rv32si-p-sbreak \
  rv32si-p-scall \
  rv32si-p-shamt

TEST_ALL=$(TEST_BASIC) $(TEST_ATOMIC) $(TEST_MULDIV) $(TEST_SUPERVISOR)

test1: $(PUT).txt
	iverilog -I$(COMMON) -DSIMULATION $(VERB) -DINITDIR=\"./\" $(IOPTS) -o yarvi $(SRC)
	./yarvi

test:
	@echo -n "  Total:   "
	@echo $(TESTS) | wc -w
	@echo -n "  Passing: "
	@for x in $(TESTS);do $(MAKE) PUT=$(TESTDIR)$$x | tee $(OUTDIR)$$x.sim;done | tee testall.log | grep 'TOHOST 00000001'|wc -l

testall:
	@echo "Basic UI tests:"
	@$(MAKE) -s TESTS="$(TEST_BASIC)" test
	@echo "Atomic tests:"
	@$(MAKE) -s TESTS="$(TEST_ATOMIC)" test
	@echo "Mul/Div tests:"
	@$(MAKE) -s TESTS="$(TEST_MULDIV)" test
	@echo "Supervisor tests:"
	@$(MAKE) -s TESTS="$(TEST_SUPERVISOR)" test
