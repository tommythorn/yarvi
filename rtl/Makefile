# -----------------------------------------------------------------------
#
# ISC License
#
# Copyright (C) 2014 - 2022  Tommy Thorn <tommy-github2@thorn.ws>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
# -----------------------------------------------------------------------

include Makefile.common
CONSTR=OrangeCrab.lpf
SPEEDGRADE=6 # My OC is -6. 8 is the fastest available (85G?)
CONFIG=$(YARVICONFIG) -DINIT_MEM=\"I-ECALL-01.hex\"
XLEN=32
NOSHIFTS=#-DNO_SHIFTS=1
SEEDS=113 117 666 1729 314 271 1204 1205 1206 1207 1208 \
1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103
SILENT=@

sweep:
	$(MAKE) --no-print-directory sweep_sub | sort -n

sweep_sub: $(foreach seed,$(SEEDS),bench_ex_$(XLEN).$(seed).config)


lint:
	verilator -Wall --lint-only --top-module yarvi_soc -DXMSB=31 -DVMSB=31 -DPMSB=14 -D $(YARVISRC)


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
	$(SILENT)yosys -DXLEN=$(XLEN) $(NOSHIFTS) -p "synth_ecp5 -json $@" $(CONFIG) $^ > $@.rpt

bench_%_$(XLEN).json: bench_%.v %.v
	$(SILENT)yosys -DXLEN=$(XLEN) -p "synth_ecp5 -json $@" $(CONFIG) $^
