// -----------------------------------------------------------------------
//
//   Copyright 2018 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

The memory, AKA load-store, unit.  If ME_READY is asserted, it will
accent a load or store operation per cycle.  Loads will come back 1 or
more cycles.  There might be multiple memory pending at any one time
(if ME_READY allows it).

*************************************************************************/

`include "yarvi.h"

module yarvi_me( input  wire             clock

               , input  wire             valid
               , input  wire             wb_en
               , input  wire [ 4:0]      wb_rd
               , input  wire [31:0]      wb_val
               , input  wire             writeenable
               , input  wire             readenable     // For hazard check
               , input  wire [ 2:0]      funct3         // 1s,2s,4,_,1u,2u,_,_
               , input  wire [31:0]      writedata

               , output reg              me_valid
               , output reg              me_wb_en
               , output reg  [ 4:0]      me_wb_rd
               , output reg  [31:0]      me_wb_val

               , output reg [`VMSB:0]    code_address
               , output reg [   31:0]    code_writedata
               , output reg [    3:0]    code_writemask
               );

   /* Data memory */
   reg [ 7:0] mem0[(1 << (`PMSB-1)) - 1:0];
   reg [ 7:0] mem1[(1 << (`PMSB-1)) - 1:0];
   reg [ 7:0] mem2[(1 << (`PMSB-1)) - 1:0];
   reg [ 7:0] mem3[(1 << (`PMSB-1)) - 1:0];

   wire [31:0] address = wb_val;

   /*
    * Reads come in with full addresses which we split into
    *
    *    | high | word index | byte index |
    *
    * read the full word, align it, and sign extended it
    */

   reg                  me_re;
   reg  [      1:0]     me_bi;
   reg  [`PMSB-2:0]     me_wi;
   reg  [     31:0]     me_address;
   reg  [      2:0]     me_funct3;
   always @(posedge clock) me_re         <= valid & readenable;
   always @(posedge clock) {me_wi,me_bi} <= address;
   always @(posedge clock) me_address    <= address;
   always @(posedge clock) me_funct3     <= funct3;

   /* Load path */

   wire [31:0] me_rd = {mem3[me_wi],mem2[me_wi],mem1[me_wi],mem0[me_wi]};
   reg  [31:0] me_rd_aligned;
   always @(*)
     case (me_bi)
       0: me_rd_aligned =        me_rd;
       1: me_rd_aligned = {24'hX,me_rd[15: 8]}; // must be byte access
       2: me_rd_aligned = {16'hX,me_rd[31:16]}; // at most half access
       3: me_rd_aligned = {24'hX,me_rd[31:24]}; // must be byte access
     endcase

   always @(*)
      if (me_re)
        case (me_funct3)
          0: me_wb_val = {{24{me_rd_aligned[ 7]}}, me_rd_aligned[ 7:0]};
          4: me_wb_val =                           me_rd_aligned[ 7:0];
          1: me_wb_val = {{16{me_rd_aligned[15]}}, me_rd_aligned[15:0]};
          5: me_wb_val =                           me_rd_aligned[15:0];
          2: me_wb_val =                           me_rd;
         default:
             me_wb_val = 32'h DEADBEEF /* X */;
      endcase
      else
             me_wb_val = me_address; // Bypass load

   always @(posedge clock) me_valid <= valid;
   always @(posedge clock) me_wb_en <= wb_en;
   always @(posedge clock) me_wb_rd <= wb_rd;

   //assert(!(valid && readenable && address[0] && funct3 > 0));
   //assert(!(valid && readenable && address[1] && funct3 > 1));

   //assert(me_funct3 == 0 || me_funct3 == 1 || me_funct3 == 2 || me_funct3 == 4 || me_funct3 == 5);

   /* Store path */

   reg [31:0] wd_aligned;
   always @(*)
     case (address[1:0])
       0: wd_aligned =              writedata;
       1: wd_aligned = {16'hX,  writedata[7:0], 8'hX}; // must be byte
       2: wd_aligned = {    writedata[15:0],   16'hX}; // at most half
       3: wd_aligned = {writedata[7:0],        24'hX}; // must be byte
     endcase

   //assert(!(valid && writeenable && address[0] && funct3 > 0));
   //assert(!(valid && writeenable && address[1] && funct3 > 1));

   reg [3:0] wd_mask;
   always @(*)
     case (funct3[1:0])
       0: wd_mask = 4'h1 << address[1:0];
       1: wd_mask = address[1] ? 4'hC : 4'h3;
       2: wd_mask = 4'hF;
       3: wd_mask = 4'hX;
     endcase

   //assert(!(valid && readenable && funct3[1:0] == 3));

   wire                 address_in_mem  = (address & (-1 << (`PMSB+1))) == 32'h80000000;
   wire                 we              = valid && writeenable & address_in_mem;
   wire [`PMSB-2:0]     wi              = address[`PMSB:2];
   always @(posedge clock) if (we & wd_mask[0]) mem0[wi] <= wd_aligned[ 7: 0];
   always @(posedge clock) if (we & wd_mask[1]) mem1[wi] <= wd_aligned[15: 8];
   always @(posedge clock) if (we & wd_mask[2]) mem2[wi] <= wd_aligned[23:16];
   always @(posedge clock) if (we & wd_mask[3]) mem3[wi] <= wd_aligned[31:24];

   always @(posedge clock) begin
      code_address   <= address;
      code_writedata <= wd_aligned;
      code_writemask <= we ? wd_mask : 0;
   end

   always @(posedge clock)
     if (we) begin
        if (0)
        $display("store %x -> [%x]/%x", wd_aligned, address, wd_mask);
        if (wd_mask == 15 & address == 'h80001000) begin
           /* XXX Hack for riscv-tests */
           $display("TOHOST = %d", wd_aligned);
           $finish;
        end
     end

   always @(posedge clock)
     if (0 && me_re)
        $display("load [%x] -> [%d] %x -> %x -> %x -> r%d",
                 me_address, me_wi, me_rd, me_rd_aligned, me_wb_val, me_wb_rd);

   /* Hazard detection */

   reg me_we;
   always @(posedge clock) me_we <= we;
   always @(posedge clock)
     /* XXX I know this isn't always true, but I need to handle this */
     if (me_we && valid && readenable && address[31:2] == me_address[31:2]) begin
        $display("Load-hit-store: load from %x hit the store to %x",
                 address, me_address);
        $finish;
     end

   /* Simulation-only */
   reg [31:0] data[(1<<(`PMSB - 1))-1:0];
   reg [31:0] i;
   initial begin
      $readmemh(`INIT_MEM, data);
      for (i = 0; i < (1<<(`PMSB - 1)); i = i + 1) begin
         mem0[i] = data[i] >>  0;
         mem1[i] = data[i] >>  8;
         mem2[i] = data[i] >> 16;
         mem3[i] = data[i] >> 24;
      end
   end
endmodule
