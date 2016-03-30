# clone and install https://github.com/thotypous/alterajtaguart.git somewhere
# and point to the relevant locations
ALTERAJTAGUART_LIB=$(PWD)/../../alterajtaguart/software
ALTERAJTAGUART_INCLUDE=$(PWD)/../../alterajtaguart/software

CXX=g++
CC=$(CXX)
CXXFLAGS=-O2 -Wall -I$(ALTERAJTAGUART_INCLUDE)
LDFLAGS=-L$(ALTERAJTAGUART_LIB) -Wl,-rpath=$(ALTERAJTAGUART_LIB)
LDLIBS=-ljtag_atlantic -ljtag_client

all: htif-jtag htif-serial

htif-jtag: htif-jtag.o $(ALTERAJTAGUART_LIB)/common.o

htif-serial: htif-serial.o
