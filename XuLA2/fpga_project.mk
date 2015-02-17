DIR_SPACES  := $(subst /, ,$(CURDIR))
DIR_NAME    := $(word $(words $(DIR_SPACES)), $(DIR_SPACES))
PROJECT     := $(DIR_NAME)

all: xula2-lx25 #xula2-lx9

.PHONY: clean

xula2-lx9: BRD=lx9
xula2-lx9:
	make -f fpga_project_rules.mk PROJECT=$(PROJECT) PART=xc6s$(BRD)-2-ftg256 BRD=$(BRD) $(PROJECT)_$(BRD).bit

xula2-lx25: BRD=lx25
xula2-lx25:
	make -f fpga_project_rules.mk PROJECT=$(PROJECT) PART=xc6s$(BRD)-2-ftg256 BRD=$(BRD) $(PROJECT)_$(BRD).bit

clean:
	make -f fpga_project_rules.mk clean
