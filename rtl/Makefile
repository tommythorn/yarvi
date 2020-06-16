SRC=htif.v yarvi_soc.v yarvi_disass.v yarvi.v yarvi_fe.v yarvi_rf.v yarvi_ex.v yarvi_me.v yarvi_alu.v
HDR=riscv.h

lint:
	verilator --lint-only --top-module yarvi_soc -DXMSB=31 -DVMSB=31 -DPMSB=14 -D $(SRC)
