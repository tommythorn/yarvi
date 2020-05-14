
status:
	$(MAKE) -s -C hello_world
	$(MAKE) -s -C riscv-tests
	$(MAKE) -s -C riscv-compliance

fpgademo:
	$(MAKE) -C BeMicroCV-A9
