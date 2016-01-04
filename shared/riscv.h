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

`define SCALLSBREAK     0
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


`define CSR_FFLAGS              'h   1
`define CSR_FRM                 'h   2
`define CSR_FCSR                'h   3                  /* alias for the frm + fflags */


/* XXX experimental, incl. the address */
`define CSR_STOREADDR           'h   8                  /* passive */
`define CSR_STORE8              'h   9                  /* WO, active */
`define CSR_STORE16             'h   a                  /* WO, active */
`define CSR_STORE32             'h   b                  /* WO, active */
`define CSR_LOAD8               'h   d
`define CSR_LOAD16              'h   e
`define CSR_LOAD32              'h   f

`define CSR_SUP0                'h 500
`define CSR_SUP1                'h 501
`define CSR_EPC                 'h 502
`define CSR_BADVADDR            'h 503
`define CSR_PTBR                'h 504
`define CSR_ASID                'h 505
`define CSR_COUNT               'h 506
`define CSR_COMPARE             'h 507
`define CSR_EVEC                'h 508
`define CSR_CAUSE               'h 509
`define CSR_STATUS              'h 50a
  `define S   [0]
  `define PS  [1]
  `define EI  [2]
  `define PEI [3]
  `define EF  [4]
  `define U64 [5]
  `define S64 [6]
  `define VM  [7]
  `define IM  [23:16]
  `define IP  [31:24]

`define CSR_HARTID              'h 50b
`define CSR_IMPL                'h 50c
`define CSR_FATC                'h 50d
`define CSR_SEND_IPI            'h 50e
`define CSR_CLEAR_IPI           'h 50f
`define CSR_TOHOST              'h 51e
`define CSR_FROMHOST            'h 51f

`define CSR_CYCLE               'h C00
`define CSR_TIME                'h C01
`define CSR_INSTRET             'h C02
`define CSR_CYCLEH              'h C80
`define CSR_TIMEH               'h C81
`define CSR_INSTRETH            'h C82


// Trap causes

`define TRAP_INST_MISALIGN      0
`define TRAP_INST_ADDR          1
`define TRAP_INST_ILLEGAL       2
`define TRAP_INST_PRIVILEGE     3
`define TRAP_FP_DISABLED        4
`define TRAP_SYSTEM_CALL        6
`define TRAP_BREAKPOINT         7
`define TRAP_LOAD_MISALIGN      8
`define TRAP_STORE_MISALIGN     9
`define TRAP_LOAD_FAULT         10
`define TRAP_STORE_FAULT        11
