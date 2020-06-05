run-tests:
	$(MAKE) -s -C sw/rv32-tests
#	$(MAKE) -s -C sw/hello_world
#	$(MAKE) -s -C sw/rv32-compliance

fpgademo:
	$(MAKE) -C target/BeMicroCV-A9
