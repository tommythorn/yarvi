SRC=htif.v yarvi_soc.v yarvi_disass.v yarvi.v yarvi_fe.v yarvi_rf.v yarvi_ex.v yarvi_me.v yarvi_alu.v
HDR=riscv.h
CONSTR=OrangeCrab.lpf
CONFIG=-DXMSB=31 -DVMSB=31 -DPMSB=13 -DTIMEOUT=$(TIMEOUT) $(VERB) -DINIT_MEM=\"I-ECALL-01.hex\"
SPEEDGRADE=6 # My OC is -6. 8 is the fastest available (85G?)

lint:
	verilator --lint-only --top-module yarvi_soc -DXMSB=31 -DVMSB=31 -DPMSB=14 -D $(SRC)

bench_alu: bench_alu.config

bench_alu.config: bench_alu.json Makefile OrangeCrab.lpf
	nextpnr-ecp5 --seed 11 --json $< --lpf OrangeCrab.lpf --textcfg $@ --85k --package CSFBGA285 --speed $(SPEEDGRADE) 2>&1 > $(basename $@).pnr.out
	@printf "%-20s %s\n" $(basename $@) "`egrep -o ': [0-9\.]+ MHz' $(basename $@).pnr.out|tail -1`"

bench_alu.json: yarvi_alu_bench.v yarvi_alu.v
	yosys -p "synth_ecp5 -json $@" $(CONFIG) $^
