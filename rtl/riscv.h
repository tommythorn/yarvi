// -----------------------------------------------------------------------
//
//   Copyright 2016,2018 Tommy Thorn - All Rights Reserved
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
`define   SRET          'h102
`define   WFI           'h105
`define   MRET          'h302
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
`define CSR_USTATUS             'h 000
`define CSR_FFLAGS              'h 001
`define CSR_FRM                 'h 002
`define CSR_FCSR                'h 003                  /* alias for the frm + fflags */
`define CSR_UIE                 'h 004
`define CSR_UTVEC               'h 005

`define CSR_USCRATCH            'h 040
`define CSR_UEPC                'h 041
`define CSR_UCAUSE              'h 042
`define CSR_UTVAL               'h 043
`define CSR_UIP                 'h 044

`define CSR_STVEC               'h 105

// User-level, counter/timers
`define CSR_CYCLE               'h C00
`define CSR_TIME                'h C01
`define CSR_INSTRET             'h C02
// ... HPMCOUNTER3 ... 31
`define CSR_CYCLEH              'h C80
`define CSR_TIMEH               'h C81
`define CSR_INSTRETH            'h C82

`define CSR_MSTATUS             'h 300
  `define UIE   [0]     // User       Interrupt Enable
  `define SIE   [1]     // Supervisor Interrupt Enable
  //      _IE   [2]     // ...        Interrupt Enable
  `define MIE   [3]     // Supervisor Interrupt Enable

  `define UPIE  [4]     // User       Previous Interrupt Enable
  `define SPIE  [5]     // Supervisor Previous Interrupt Enable
  //      _PIE  [6]     // ...        Previous Interrupt Enable
  `define MPIE  [7]     // Supervisor Previous Interrupt Enable

  //      UPP   []      // User       Previous Privilege Level
  `define SPP   [8]     // Supervisor Previous Privilege Level
  `define MPP   [12:11] // Machine    Previous Privilege Level

  `define FS    [14:13]  // Floating-point status {Off, Initial, Clean, Dirty}
  `define XS    [16:15]  // Same for user-mode extensions
  `define MPRV  [17]     // modifies the privilege level of loads/stores
  `define SUM   [18]     // permit Supervisor User Memory access
  `define MXR   [19]     // Make eXecutable Readable
  `define TVM   [20]     // Trap Virtual Memory
  `define TW    [21]     // Timeout Wait
  `define TSR   [22]     // Trap SRET
  `define SD    [31]     // Summary Dirty (FS==11 || XS==11)

`define CSR_SATP                'h 180

`define CSR_MISA                'h 301
`define CSR_MEDELEG             'h 302
`define CSR_MIDELEG             'h 303
`define CSR_MIE                 'h 304
`define CSR_MTVEC               'h 305
`define CSR_MCOUNTEREN          'h 306

`define CSR_MSCRATCH            'h 340
`define CSR_MEPC                'h 341
`define CSR_MCAUSE              'h 342
`define CSR_MTVAL               'h 343
`define CSR_MIP                 'h 344

`define CSR_PMPCFG0             'h 3A0
`define CSR_PMPADDR0            'h 3B0

`define CSR_MCYCLE              'h B00
`define CSR_MINSTRET            'h B02

`define CSR_MCYCLEH             'h B80
`define CSR_MINSTRETH           'h B82

// Machine-level
`define CSR_MVENDORID           'h F11
`define CSR_MARCHID             'h F12
`define CSR_MIMPID              'h F13
`define CSR_MHARTID             'h F14

// Official YARVI Architecture ID for
`define    VENDORID_YARVI       9

// Trap causes

`define CAUSE_MISALIGNED_FETCH    'h0
`define CAUSE_FAULT_FETCH         'h1
`define CAUSE_ILLEGAL_INSTRUCTION 'h2
`define CAUSE_BREAKPOINT          'h3
`define CAUSE_MISALIGNED_LOAD     'h4
`define CAUSE_FAULT_LOAD          'h5
`define CAUSE_MISALIGNED_STORE    'h6
`define CAUSE_FAULT_STORE         'h7
`define CAUSE_USER_ECALL          'h8
`define CAUSE_SUPERVISOR_ECALL    'h9
`define CAUSE_HYPERVISOR_ECALL    'ha
`define CAUSE_MACHINE_ECALL       'hb
`define CAUSE_FETCH_PAGE_FAULT    'hc
`define CAUSE_LOAD_PAGE_FAULT     'hd
`define CAUSE_STORE_PAGE_FAULT    'hf

// Priviledge levels
`define PRV_U 0
`define PRV_S 1
`define PRV_H 2
`define PRV_M 3
