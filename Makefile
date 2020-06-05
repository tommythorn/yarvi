run-tests:
	$(MAKE) -s -C sw/rv32-compliance
	$(MAKE) -s -C sw/rv32-tests
#	$(MAKE) -s -C sw/hello_world

fpgademo:
	$(MAKE) -C target/BeMicroCV-A9
