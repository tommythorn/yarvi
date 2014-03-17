// -----------------------------------------------------------------------
//
//   Copyright 2014 Tommy Thorn - All Rights Reserved
//
//   This program is free software; you can redistribute it and/or modify
//   it under the terms of the GNU General Public License as published by
//   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
//   Bostom MA 02111-1307, USA; either version 2 of the License, or
//   (at your option) any later version; incorporated herein by reference.
//
// -----------------------------------------------------------------------

`define LOAD		 0
`define LOAD_FP	         1
`define CUSTOM0		 2
`define MISC_MEM	 3
`define OP_IMM		 4
`define AUIPC		 5
`define OP_IMM_32	 6
`define EXT0		 7
`define STORE		 8
`define STORE_FP	 9
`define CUSTOM1		10
`define AMO		11
`define OP		12
`define LUI		13
`define OP_32		14
`define EXT1		15
`define MADD		16
`define MSUB		17
`define NMSUB		18
`define NMADD		19
`define OP_FP		20
`define RES1		21
`define CUSTOM2		22
`define EXT2		23
`define BRANCH		24
`define JALR		25
`define RES0		26
`define JAL		27
`define SYSTEM		28
`define RES2		29
`define CUSTOM3		30
`define EXT3		31

`define ADDSUB		0
`define SLL		1
`define SLT		2
`define SLTU		3
`define XOR		4
`define SR_		5
`define OR		6
`define AND		7

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
