all:  check-speed lint run-tests
	grep MHz target/OrangeCrab/nextpnr-ecp5.out|tail -1

lint:
	$(MAKE) -s -C rtl

run-tests:
	$(MAKE) -s -C sw/rv32-compliance
	$(MAKE) -s -C sw/rv32-tests
	@echo "Expect 46 passing"
#	$(MAKE) -s -C sw/hello_world

check-speed:
	-$(MAKE) -C target/OrangeCrab top_out.config
