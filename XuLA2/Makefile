RVPATH=
RVPREFIX=$(RVPATH)riscv64-unknown-elf-

run: load
	python xula2.py

load: xula2_lx25.bit
	xsload.py --fpga xula2_lx25.bit
	touch load

xula2_lx25.bit: xula2-lx25

include fpga_project.mk
