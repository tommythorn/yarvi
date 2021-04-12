include Makefile.common
CONSTR=OrangeCrab.lpf
SPEEDGRADE=6 # My OC is -6. 8 is the fastest available (85G?)
CONFIG=$(YARVICONFIG) -DINIT_MEM=\"I-ECALL-01.hex\"
XLEN=64
SEEDS=113 117 42 666 74 1729 73 314 271 1204 1205 1206 1207 1208 99 98 97 96 88 77 33 55 66 89
SILENT=@

sweep:
	$(MAKE) --no-print-directory sweep_sub | sort -n

sweep_sub: $(foreach seed,$(SEEDS),bench_ex_$(XLEN).$(seed).config)


lint:
	verilator --lint-only --top-module yarvi_soc -DXMSB=31 -DVMSB=31 -DPMSB=14 -D $(YARVISRC)


bench_alu: bench_alu_$(XLEN).config

bench_ex_$(XLEN).%.config: bench_ex_$(XLEN).json Makefile OrangeCrab.lpf
	-$(SILENT)nextpnr-ecp5 --seed=$(patsubst bench_ex_$(XLEN).%.config,%,$@) \
		--json $< --lpf OrangeCrab.lpf --textcfg $@ --85k \
	       	--package CSFBGA285 --speed $(SPEEDGRADE) > $@.rpt 2>&1 || true
	-$(SILENT)printf "%s %s\n" "`egrep -o ': [0-9\.]+ MHz' $@.rpt | tail -1`" $@

bench_%_$(XLEN).$(SEED).config: bench_%_$(XLEN).json Makefile OrangeCrab.lpf
	-$(SILENT)nextpnr-ecp5 --seed=$(SEED) --json $< --lpf OrangeCrab.lpf --textcfg $@ --85k \
	       --package CSFBGA285 --speed $(SPEEDGRADE) > $@.rpt 2>&1
	$(SILENT)printf "%-20s %s\n" $@ "`egrep -o ': [0-9\.]+ MHz' $@.rpt | tail -1`"

bench_ex_$(XLEN).json: bench_ex.v ex.v alu.v
	$(SILENT)yosys -DXLEN=$(XLEN) -p "synth_ecp5 -json $@" $(CONFIG) $^ > $@.rpt

bench_%_$(XLEN).json: bench_%.v %.v
	$(SILENT)yosys -DXLEN=$(XLEN) -p "synth_ecp5 -json $@" $(CONFIG) $^
