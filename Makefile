
status:
	$(MAKE) -s -C riscv-tests
	$(MAKE) -s -C riscv-compliance

fpgademo:
	$(MAKE) -C BeMicroCV-A9
