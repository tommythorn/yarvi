// -----------------------------------------------------------------------
//
//   Copyright 2016 Tommy Thorn - All Rights Reserved
//
//   This program is free software; you can redistribute it and/or modify
//   it under the terms of the GNU General Public License as published by
//   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
//   Bostom MA 02111-1307, USA; either version 2 of the License, or
//   (at your option) any later version; incorporated herein by reference.
//
// -----------------------------------------------------------------------

`define LOAD             0
`define LOAD_FP          1
`define CUSTOM0          2
`define MISC_MEM         3
`define   FENCE             0 // funct3
`define   FENCE_I           1
`define OP_IMM           4
`define AUIPC            5
`define OP_IMM_32        6
`define EXT0             7
`define STORE            8
`define STORE_FP         9
`define CUSTOM1         10
`define AMO             11
`define OP              12
`define LUI             13
`define OP_32           14
`define EXT1            15
`define MADD            16
`define MSUB            17
`define NMSUB           18
`define NMADD           19
`define OP_FP           20
`define RES1            21
`define CUSTOM2         22
`define EXT2            23
`define BRANCH          24
`define JALR            25
`define RES0            26
`define JAL             27
`define SYSTEM          28
`define RES2            29
`define CUSTOM3         30
`define EXT3            31

`define ADDSUB          0
`define SLL             1
`define SLT             2
`define SLTU            3
`define XOR             4
`define SR_             5
`define OR              6
`define AND             7

`define PRIV            0
`define   ECALL             0
`define   EBREAK            1
`define   ERET            256
`define CSRRW           1
`define CSRRS           2
`define CSRRC           3
`define CSRRWI          5
`define CSRRSI          6
`define CSRRCI          7

`define opext    [1 : 0]
`define opcode   [6 : 2]
`define rd       [11: 7]
`define funct3   [14:12]
`define rs1      [19:15]
`define rs2      [24:20]
`define funct7   [31:25]

`define br_negate   [12]
`define br_unsigned [13]
`define br_rela     [14]

`define imm11_0  [31:20]


/**  Control and Status Registers  **/

// User-level, floating-point
`define CSR_FFLAGS              'h   1
`define CSR_FRM                 'h   2
`define CSR_FCSR                'h   3                  /* alias for the frm + fflags */

// User-level, counter/timers
`define CSR_CYCLE               'h C00
`define CSR_TIME                'h C01
`define CSR_INSTRET             'h C02
`define CSR_CYCLEH              'h C80
`define CSR_TIMEH               'h C81
`define CSR_INSTRETH            'h C82

// Machine-level
`define CSR_MCPUID              'h F00
`define CSR_MIMPID              'h F01
`define CSR_MHARTID             'h F10

`define CSR_MSTATUS             'h 300
  `define EI   [0]      // Interrupt Enable
  `define PRV  [2:1]    // Current privilege mode
  `define EI1  [3]      // stack of these ...
  `define PRV1 [5:4]
  `define EI2  [6]
  `define PRV2 [8:7]
  `define EI3  [9]
  `define PRV3 [11:10]
  `define FS   [13:12]  // Floating-point status {Off, Initial, Clean, Dirty}
  `define XS   [15:14]  // Same for user-mode extensions
  `define MPRV [16]     // modifies the privilege level of loads/stores
  `define VM   [21:17]  // Active virtualization mode
  `define SD   [31]     // FS==11 || XS==11

`define CSR_MTVEC               'h 301
`define CSR_MTDELEG             'h 302
`define CSR_MIE                 'h 304
`define CSR_MTIMECMP            'h 321

`define CSR_MTIME               'h 701
`define CSR_MTIMEH              'h 741

`define CSR_MSCRATCH            'h 340
`define CSR_MEPC                'h 341
`define CSR_MCAUSE              'h 342
`define CSR_MBADADDR            'h 343
`define CSR_MIP                 'h 344
  `define MTIP [7]

`define CSR_MBASE               'h 380
`define CSR_MBOUND              'h 381
`define CSR_MIBASE              'h 382
`define CSR_MIBOUND             'h 383
`define CSR_MDBASE              'h 384
`define CSR_MDBOUND             'h 385

// User-level, counter/timers
`define CSR_CYCLEW              'h 900
`define CSR_TIMEW               'h 901
`define CSR_INSTRETW            'h 902
`define CSR_CYCLEHW             'h 980
`define CSR_TIMEHW              'h 981
`define CSR_INSTRETHW           'h 982

`define CSR_HTIMEW              'h B01
`define CSR_HTIMEHW             'h B81

`define CSR_MTOHOST             'h 780
`define CSR_MFROMHOST           'h 781


// Trap causes

`define TRAP_INST_MISALIGN      0
`define TRAP_INST_ADDR          1
`define TRAP_INST_ILLEGAL       2
`define TRAP_BREAKPOINT         3
`define TRAP_LOAD_MISALIGN      4
`define TRAP_LOAD_FAULT         5
`define TRAP_STORE_MISALIGN     6
`define TRAP_STORE_FAULT        7
`define TRAP_ECALL_UMODE        8
`define TRAP_ECALL_SMODE        9
`define TRAP_ECALL_HMODE        10
`define TRAP_ECALL_MMODE        11
