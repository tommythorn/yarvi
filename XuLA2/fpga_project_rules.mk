ifeq ($(shell uname),Linux)
  MKDIR:=mkdir
else
  MKDIR:=gmkdir
endif

$(PROJECT).vhd:
	echo $(PROJECT)

$(PROJECT)_$(BRD).ngc: $(PROJECT).vhd
	$(MKDIR) -p xst/projnav.tmp/
	xst -intstyle ise -ifn $(PROJECT)_$(BRD).xst -ofn $(PROJECT)_$(BRD).syr
	mv $(PROJECT).ngc $(PROJECT)_$(BRD).ngc

$(PROJECT)_$(BRD).ngd: $(PROJECT)_$(BRD).ngc
	ngdbuild -intstyle ise -dd _ngo -nt timestamp \
	-uc $(PROJECT).ucf -aul -p $(PART) $(PROJECT)_$(BRD).ngc $(PROJECT)_$(BRD).ngd

$(PROJECT)_$(BRD).ncd: $(PROJECT)_$(BRD).ngd
	map -intstyle ise -p $(PART) \
	-w -detail -ir off -ignore_keep_hierarchy -pr b -timing -ol high -logic_opt on  \
	-o $(PROJECT)_$(BRD).ncd $(PROJECT)_$(BRD).ngd $(PROJECT)_$(BRD).pcf

$(PROJECT)_$(BRD)_routed.ncd: $(PROJECT)_$(BRD).ncd
	par -w -intstyle ise -ol high $(PROJECT)_$(BRD).ncd $(PROJECT)_$(BRD)_routed.ncd $(PROJECT)_$(BRD).pcf

$(PROJECT)_$(BRD).bit: $(PROJECT)_$(BRD)_routed.ncd
	bitgen -f $(PROJECT).ut $(PROJECT)_$(BRD)_routed.ncd $(PROJECT)_$(BRD).bit

clean:
	-rm -f *.ngc
	-rm -f *.ngd
	-rm -f *.ncd
	-rm -f *.pcf
	-rm -f *.lso
	-rm -f *.ngr
	-rm -f *.bgn
	-rm -f *.bld
	-rm -f *.cmd_log
	-rm -f *.drc
	-rm -f *.gise
	-rm -f *.map
	-rm -f *.mrp
	-rm -f *.ngm
	-rm -f *.syr
	-rm -f *.xwbt
	-rm -f *.xrpt
	-rm -f *.pad
	-rm -f *.par
	-rm -f *.psr
	-rm -f *.ptwx
	-rm -f *.unroutes
	-rm -f *.xpi
	-rm -f *.csv
	-rm -f *.xml
	-rm -f *.html
	-rm -f *.xrpt
	-rm -f *.log
	-rm -f *.stx
	-rm -f *.tcl
	-rm -f *.txt
	-rm -f *.twr
	-rm -f *.twx
	-rm -rf _ngo
	-rm -rf _xmsgs
	-rm -rf xlnx_*
	-rm -rf ipcore_dir
	-rm -rf iseconfig
	-rm -rf templates
	-rm -rf xst
