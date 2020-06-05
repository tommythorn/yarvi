Introduction
=============

This directory contains some examples on using the `jtag_atlantic` library from Altera to communicate with the JTAG UART from C++ programs.

Documentation about the library is available as comments inside `jtag_atlantic.h`. Beware this is not official documentation.

Building the examples
=====================

* Copy `libjtag_atlantic.so` and `libjtag_client.so` from your Quartus installation to this directory before building. Pay attention to copy the files corresponding to the correct processor architecture, i.e. if you are using x86\_64, copy the library files from the `quartus/linux64` directory inside your installation.
* Type `make`.

About the examples
==================

* `echohello.cpp` is intended to be used together with `ExampleEcho.bsv`. It sends some strings to the UART, receives the returned data and prints it to the console.
* `counterperf.cpp` is intended to be used together with `ExampleCounter.bsv`. It reads data from the counter, validates the data, and measures the data rate in bit/s. A rate of about 1 Mbit/s should be expected.

Known caveats
=============

Sometimes `jtagatlantic_read` persists in returning `-1` even if no error ocurred (well, at least `jtagatlantic_get_error` did not return any error code in these cases) and only goes back to returning useful data when the device is closed and reopened. This appears to occur when the data rate is too fast and can often be observed when running `counterperf`.

Using the libraries in your code
================================

Just include `jtag_atlantic.h` and use the API. Link your final executable to both `jtag_atlantic` and `jtag_client` libraries. You can use the `Makefile` as a starting point or just build manually as follows:

    g++ -L/path/to/libs -O2 -Wall program.cpp -ljtag_atlantic -ljtag_client -o program

Do not forget to add the path to the libraries also to `LD_LIBRARY_PATH`. Another option is to set a rpath, like what is done in the `Makefile`, by adding `-Wl,-rpath=/path/to/libs` to the command above.
