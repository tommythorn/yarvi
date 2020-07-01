include Makefile.common
CONSTR=OrangeCrab.lpf
SPEEDGRADE=6 # My OC is -6. 8 is the fastest available (85G?)
CONFIG=$(YARVICONFIG) -DINIT_MEM=\"I-ECALL-01.hex\"

lint:
	verilator --lint-only --top-module yarvi_soc -DXMSB=31 -DVMSB=31 -DPMSB=14 -D $(YARVISRC)

bench_alu: bench_alu.config

bench_alu.config: bench_alu.json Makefile OrangeCrab.lpf
	nextpnr-ecp5 --seed 11 --json $< --lpf OrangeCrab.lpf --textcfg $@ --85k --package CSFBGA285 --speed $(SPEEDGRADE) 2>&1 > $(basename $@).pnr.out
	@printf "%-20s %s\n" $(basename $@) "`egrep -o ': [0-9\.]+ MHz' $(basename $@).pnr.out|tail -1`"

bench_alu.json: yarvi_alu_bench.v yarvi_alu.v
	yosys -p "synth_ecp5 -json $@" $(CONFIG) $^
