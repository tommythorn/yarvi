# Adjust to match your RISC-V toolchain
RVPATH=/opt/rvc/bin/
RVPREFIX=$(RVPATH)riscv64-unknown-elf-

CC=$(RVPREFIX)gcc -std=gnu99 -m32 -O

all: hw.riscv.dis mem0.txt
	$(MAKE) -C ../BeMicro-CV hw.sim

mem3.txt mem2.txt mem1.txt mem0.txt: program.txt
	cut -c1-2 program.txt > mem3.txt
	cut -c3-4 program.txt > mem2.txt
	cut -c5-6 program.txt > mem1.txt
	cut -c7-8 program.txt > mem0.txt

program.txt: hw.bin
	hexdump -e '"%08x\n"' $^ > $@

hw.bin: hw.riscv
	$(RVPREFIX)objcopy -O binary $^ $@

hw.riscv.dis: hw.riscv
	$(RVPREFIX)objdump -d $^ > $@

hw.riscv: crt0.o hw.o
	$(RVPREFIX)ld -Tyarvi.ld -melf32lriscv -o $@ $^
