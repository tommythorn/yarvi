run-tests:
#	$(MAKE) -s -C sw/hello_world
	$(MAKE) -s -C sw/riscv-tests
	$(MAKE) -s -C sw/riscv-compliance

fpgademo:
	$(MAKE) -C target/BeMicroCV-A9
