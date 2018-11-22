#TRACE=--trace
TRACE=
obj_dir/Vyarvi_soc: ../core/yarvi_soc.v sim_main.cpp
	verilator -Wall $(TRACE) -DINIT_MEM=\"rv32ui-p-simple.hex\" -I../core --cc yarvi_soc.v --exe sim_main.cpp
	make -C obj_dir -f Vyarvi_soc.mk Vyarvi_soc
	obj_dir/Vyarvi_soc

SRC=toplevel.v \
    ../../../red-lava/simulation/altsyncram.v \
    ../../../red-lava/simulation/lpm_add_sub.v

sim: obj_dir/Vtoplevel
	@for x in *.mif;do grep : < $$x|sed -e "s,^.*:,," -e "s,;,," > $$x.txt;done
	@./obj_dir/Vtoplevel

obj_dir/Vtoplevel: $(SRC)
	@verilator --cc toplevel.v ../../../red-lava/simulation/altsyncram.v --exe sim_main.cpp 2>&1 > /dev/null
	@make -C obj_dir -j -f Vtoplevel.mk >/dev/null 2>&1

