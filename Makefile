all:
	$(MAKE) -C shared
	$(MAKE) -C BeMicro-CV hw.sim |head -200


