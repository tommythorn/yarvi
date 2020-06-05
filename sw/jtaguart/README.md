Introduction
=============

The Altera JTAG UART is a serial interface which can be used for bidirectional communications between a FPGA and a computer. Like the [AltSourceProbe](https://github.com/thotypous/altsourceprobe) module, it can be used as a *portable* bus supported across all Altera FPGAs, due to the ubiquity of JTAG pins in these devices, which in development kits are readily acessible in a computer using the same USB cable as used for programming the FPGA. However, Altera JTAG UART is much faster than AltSourceProbe, being able to achieve data rates in the order of 1 Mbit/s, though AltSourceProbe is best suited and easier to use for debugging hardware designs, whereas the UART is better for transferring larger amounts of data or test vectors.

Similar work
============

An implementation similar to ours is [available](http://asim.csail.mit.edu/redmine/projects/leap-platforms/repository/entry/trunk/modules/bluespec/common/fpgaenv/physical-platform/physical-devices/jtag/altera/AvalonJtag.bsv) from Intel/MIT designers, but it has a larger overhead because it uses an internal Avalon bus in order to be able to access an Altera JTAG UART instantiated by SOPCBuilder/QSYS. Our implementation, on the other hand, uses directly the *undocumented* `alt_jtag_atlantic` megafunction.

AlteraJtagUart interface
========================

Our module is available in a single file: `AlteraJtagUart.bsv`. Just copy this file to your design, import it, and instantiate the `mkAlteraJtagUart` module passing as parameters the binary logarithm of the desired size for the receive and transmit FIFOs.

Examples
========

* `ExampleEcho.bsv` implements an echo. It simply transmits back to the computer every byte received via the UART.
* `ExampleCounter.bsv` implements a counter which continually sends bytes 0 to 255 to the UART. This example also discards any data received.

Software
========

This repository also contains instructions on how to communicate with the Altera JTAG UART using C++ programs. Please take a look at the `software` subdirectory for further information.
