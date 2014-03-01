all: yarvi
	./yarvi

yarvi: yarvi.v
	iverilog -o yarvi yarvi.v

