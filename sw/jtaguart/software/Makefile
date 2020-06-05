CXX=g++
CC=$(CXX)
CXXFLAGS=-O2 -Wall
LDFLAGS=-L. -Wl,-rpath=.
LDLIBS=-ljtag_atlantic -ljtag_client
all: echohello counterperf
echohello: echohello.o common.o
counterperf: counterperf.o common.o
clean:
	rm -f echohello echohello.o counterperf counterperf.o common.o
