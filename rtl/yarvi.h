`timescale 1ns/10ps

`include "riscv.h"

`define INIT_PC    32'h8000_0000
`define DATA_START 32'h8000_0000
`ifndef INITDIR
`define INITDIR ""
`endif

`ifndef INIT_MEM
`define INIT_MEM "init_mem.hex"
`endif

`define DC_WORDS_LG2 13 // 32 KiB
`define DC_WORDS (1 << `DC_WORDS_LG2)
`define DC_LINE_WORDS_LG2 1 // 2^1 64-bit words = 16 byte line size


// The execution environment really should explicitly provide the configuration,
// definitely XMSB (=XLEN-1), VMSB (=PA-1), and PMSB (=PA-1)
// `define VMSB 31  // Virtual address MSB
// `define PMSB 14  // Physical bits.  We implement 32 KiB = 2^15
// `define XMSB 31  // XLEN-1
