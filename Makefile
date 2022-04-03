all: comply test ipc fmax
	grep MHz target/OrangeCrab/nextpnr-ecp5.out|tail -1

alu_bench:
	$(MAKE) -s -C rtl

# It's my experience that compliance tests catches many bugs that rv32-tests doesn't
comply:
	$(MAKE) -s -C sw/rv32-compliance

test:
	$(MAKE) -s -C sw/rv32-tests
	@echo "Expect 46 passing"

ipc:
#	$(MAKE) -s -C sw/dhrystone
	$(MAKE) -s -C target/verisim

fmax:
	-$(MAKE) -C target/OrangeCrab sweep
