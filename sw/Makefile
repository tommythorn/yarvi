# clone and install https://github.com/thotypous/alterajtaguart.git somewhere
# and point to the relevant locations
ALTERAJTAGUART_LIB=../../alterajtaguart/software
ALTERAJTAGUART_INCLUDE=../../alterajtaguart/software

CXX=g++
CC=$(CXX)
CXXFLAGS=-O2 -Wall -I$(ALTERAJTAGUART_INCLUDE)
LDFLAGS=-L$(ALTERAJTAGUART_LIB) -Wl,-rpath=.
LDLIBS=-ljtag_atlantic -ljtag_client

all: htif-jtag htif-serial

htif-jtag: htif-jtag.o $(ALTERAJTAGUART_LIB)/common.o

htif-serial: htif-serial.o
