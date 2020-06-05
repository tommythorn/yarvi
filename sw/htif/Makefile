# clone and install https://github.com/thotypous/alterajtaguart.git somewhere
# and point to the relevant locations
ALTERAJTAGUART_LIB=$(shell pwd)/alterajtaguart/software
ALTERAJTAGUART_INCLUDE=alterajtaguart/software

CXX=g++
CC=$(CXX)
CXXFLAGS=-O2 -Wall -I$(ALTERAJTAGUART_INCLUDE)
LDFLAGS=-L$(ALTERAJTAGUART_LIB) -Wl,-rpath=$(ALTERAJTAGUART_LIB)
LDLIBS=-ljtag_atlantic -ljtag_client

all: htif-jtag htif-serial

htif-jtag: htif-jtag.o \
	$(ALTERAJTAGUART_LIB)/common.o \
	$(ALTERAJTAGUART_LIB)/libjtag_client.so \
	$(ALTERAJTAGUART_LIB)/libjtag_atlantic.so

htif-serial: htif-serial.o


$(ALTERAJTAGUART_LIB)/libjtag_client.so:
	cp $$(dirname $$(which quartus))/../linux64/libjtag_client.so $(ALTERAJTAGUART_LIB)

$(ALTERAJTAGUART_LIB)/libjtag_atlantic.so:
	cp $$(dirname $$(which quartus))/../linux64/libjtag_atlantic.so $(ALTERAJTAGUART_LIB)

