`timescale 1ns/10ps

`include "riscv.h"

`define INIT_PC    64'h8000_0000
`define DATA_START 64'h8000_0000
`ifndef INITDIR
`define INITDIR ""
`endif

`define DC_WORDS_LG2 15 // 128 KiB
`define DC_WORDS (1 << `DC_WORDS_LG2)
`define DC_LINE_WORDS_LG2 1 // 2^1 64-bit words = 16 byte line size

`define VMSB 38  // Virtual address MSB
`define XMSB 63  // XLEN-1

