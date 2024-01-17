CORE=../../rtl
include $(CORE)/Makefile.common

SRC=	../../rtl/yarvi.v \
	../../rtl/yarvi_disass.v \
	../../rtl/alu.v \
	../../rtl/yarvi_dec_reg_usage.v \
	../../rtl/yarvi_ld_align.v \
	../../rtl/yarvi_st_align.v \
	altsyncram.v lpm_add_sub.v

CONFIG=-I$(CORE) $(YARVICONFIG) -DINIT_MEM=\"dhry.hex\" -DQUIET -DTOHOST=10000000 -DKEEP_GOING

#TRACE=--trace
TRACE=
obj_dir/Vyarvi: $(SRC) sim_main.cpp Makefile dhry.0.hex dhry.1.hex dhry.2.hex dhry.3.hex
	verilator -Wall --top-module yarvi \
	    $(CONFIG) --cc $(SRC) --exe sim_main.cpp
	make -C obj_dir -f Vyarvi.mk Vyarvi
	$@ +INIT0=dhry.0.hex +INIT1=dhry.1.hex +INIT2=dhry.2.hex +INIT3=dhry.3.hex

sim: obj_dir/Vtoplevel dhry.0.hex dhry.1.hex dhry.2.hex dhry.3.hex
	@for x in *.mif;do grep : < $$x|sed -e "s,^.*:,," -e "s,;,," > $$x.txt;done
	@./obj_dir/Vtoplevel +INIT0=dhry.0.hex +INIT1=dhry.1.hex +INIT2=dhry.2.hex +INIT3=dhry.3.hex


obj_dir/Vtoplevel: $(SRC)
	@verilator --cc toplevel.v ../../../red-lava/simulation/altsyncram.v --exe sim_main.cpp 2>&1 > /dev/null
	@make -C obj_dir -j -f Vtoplevel.mk >/dev/null 2>&1

