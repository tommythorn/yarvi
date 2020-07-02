// -----------------------------------------------------------------------
//
//   Copyright 2018,2020 Tommy Thorn - All Rights Reserved
//
// -----------------------------------------------------------------------

/*************************************************************************

The memory, AKA load-store, unit.  If ME_READY is asserted, it will
accept a load or store operation per cycle.  Loads will come back 1 or
more cycles.  There might be multiple memory pending at any one time
(if ME_READY allows it).

*************************************************************************/

`include "yarvi.h"

module yarvi_me( input  wire             clock
               , input  wire             reset

               , input  wire             valid
               , input  wire [31:0]      pc
               , input  wire [ 4:0]      wb_rd
               , input  wire [31:0]      wb_val
               , input  wire             writeenable
               , input  wire             readenable     // For hazard check
               , input  wire [ 2:0]      funct3         // 1s,2s,4,_,1u,2u,_,_
               , input  wire [31:0]      writedata

               , output reg              me_valid
               , output reg  [31:0]      me_pc
               , output reg  [ 4:0]      me_wb_rd
               , output wire[`XMSB:0]    me_wb_val
               , output reg              me_exc_misaligned
               , output reg [`XMSB:0]    me_exc_mtval
               , output reg              me_load_hit_store
               , output reg              me_timer_interrupt

               , output reg [`VMSB:2]    code_address
               , output reg [   31:0]    code_writedata
               , output reg [    3:0]    code_writemask
               );

   /* Data memory */
   reg [ 7:0] mem0[(1 << (`PMSB-1)) - 1:0];
   reg [ 7:0] mem1[(1 << (`PMSB-1)) - 1:0];
   reg [ 7:0] mem2[(1 << (`PMSB-1)) - 1:0];
   reg [ 7:0] mem3[(1 << (`PMSB-1)) - 1:0];

   reg [63:0] mtime;
   reg [63:0] mtimecmp;

   wire [31:0] address = wb_val;
   wire        address_in_mem  = (address & (-1 << (`PMSB+1))) == 32'h80000000;

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
   reg                  me_address_in_mem;
   always @(posedge clock) me_re         <= valid & readenable;
   always @(posedge clock) {me_wi,me_bi} <= address[`PMSB:0];
   always @(posedge clock) me_address    <= address;
   always @(posedge clock) me_funct3     <= funct3;
   always @(posedge clock) me_address_in_mem <= address_in_mem;

   reg                  misaligned;
   always @(*)
     case (funct3[1:0])
       0: misaligned =  0;            // Byte
       1: misaligned =  address[  0]; // Half
       2: misaligned = |address[1:0]; // Word
       3: misaligned =  1'hX;
     endcase

   /* Load path */

   wire [31:0] me_rd = {mem3[me_wi],mem2[me_wi],mem1[me_wi],mem0[me_wi]};
// SOON, we just need to move the address calculation up
// reg [31:0]           me_rd = 0;
// always @(posedge clock) me_rd <= {mem3[me_wi],mem2[me_wi],mem1[me_wi],mem0[me_wi]};


   /* Memory mapped io devices (only word-wide accesses are allowed) */
   // XXX me_rd_other should be folded into the bypass load register
   // to avoid the late mux in the load path
   reg [31:0]  me_rd_other;
   always @(*)
     case (me_wi)
       0: me_rd_other = mtime[31:0]; // XXX  or uart
       1: me_rd_other = mtime[63:32];
       2: me_rd_other = mtimecmp[31:0];
       3: me_rd_other = mtimecmp[63:32];
       default:
          me_rd_other = 0;
     endcase

   yarvi_ld_align yarvi_ld_align1
     (!me_re, me_address,
      me_funct3, me_bi, me_address_in_mem ? me_rd : me_rd_other,
      me_wb_val);

   /* Store path */

   wire [`XMSB:0] st_data;
   wire [    3:0] st_mask;

   yarvi_st_align yarvi_st_align1
     (funct3, address[1:0], writedata, st_mask, st_data);

   wire                 we              = valid && writeenable & address_in_mem & !misaligned;
   wire [`PMSB-2:0]     wi              = address[`PMSB:2];
   always @(posedge clock) if (we & st_mask[0]) mem0[wi] <= st_data[ 7: 0];
   always @(posedge clock) if (we & st_mask[1]) mem1[wi] <= st_data[15: 8];
   always @(posedge clock) if (we & st_mask[2]) mem2[wi] <= st_data[23:16];
   always @(posedge clock) if (we & st_mask[3]) mem3[wi] <= st_data[31:24];

   /* Memory mapped io devices (only word-wide accesses are allowed) */
   always @(posedge clock) if (reset) begin
      mtime 				<= 0;
      mtimecmp 				<= 0;
   end else begin
      mtime 				<= mtime + 1; // XXX Yes, this is terrible
      me_timer_interrupt 		<= mtime > mtimecmp;

      if (valid && writeenable && (address & 32'h4FFFFFF3) == 32'h40000000)
        case (address[3:2])
          0: mtime[31:0]		<= writedata;
          1: mtime[63:32]		<= writedata;
          2: mtimecmp[31:0]		<= writedata;
          3: mtimecmp[63:32]		<= writedata;
        endcase
   end

   always @(posedge clock) begin
      code_address   <= address[`VMSB:2];
      code_writedata <= st_data;
      code_writemask <= we ? st_mask : 0;
   end

`ifdef TOHOST
   reg  [`VMSB  :0] dump_addr;
`endif
   always @(posedge clock)
     if (!reset && valid && writeenable & !misaligned) begin
        if (!address_in_mem)
          $display("store %x -> [%x]/%x", st_data, address, st_mask);

`ifdef TOHOST
        if (st_mask == 15 & address == 'h`TOHOST) begin
           /* XXX Hack for riscv-tests */
           $display("TOHOST = %d", st_data);

`ifdef BEGIN_SIGNATURE
           $display("Signature Begin");
           for (dump_addr = 'h`BEGIN_SIGNATURE; dump_addr < 'h`END_SIGNATURE; dump_addr=dump_addr+4)
              $display("%x", {mem3[dump_addr[`PMSB:2]], mem2[dump_addr[`PMSB:2]], mem1[dump_addr[`PMSB:2]], mem0[dump_addr[`PMSB:2]]});
`endif
           $finish;
        end
`endif
     end

   /* Hazard detection */

   reg me_we;
   always @(posedge clock) begin
      if (me_exc_misaligned | me_load_hit_store) begin
         me_valid 		<= 0;
         me_wb_rd		<= 0;
      end else begin
         me_valid		<= valid;
         me_wb_rd		<= wb_rd;
      end
      me_pc 			<= pc;
      me_we 			<= we;
      me_load_hit_store 	<= 0;
      me_exc_misaligned 	<= 0;
      me_exc_mtval              <= address;

      if (valid & misaligned & (readenable | writeenable)) begin
         me_exc_misaligned 	<= 1;
         me_valid 		<= 0;
         me_wb_rd 		<= 0;
         $display("%5d  ME: %x misaligned load/store address %x", $time/10, pc, address);
      end else if (valid && readenable && me_we && address[31:2] == me_address[31:2]) begin
         me_load_hit_store 	<= 1;
         me_valid 		<= 0;
         me_wb_rd 		<= 0;
         $display("%5d  ME: %x load-hit-store: load from address %x hit the store to address %x",
                  $time/10, pc, address, me_address);
      end
   end

`ifdef SIMULATION
   /* Simulation-only */
   reg [31:0] data[(1<<(`PMSB - 1))-1:0];
   reg [31:0] i;
   initial begin
      $readmemh(`INIT_MEM, data);
      for (i = 0; i < (1<<(`PMSB - 1)); i = i + 1) begin
         mem0[i] = data[i][7:0];
         mem1[i] = data[i][15:8];
         mem2[i] = data[i][23:16];
         mem3[i] = data[i][31:24];
      end
   end
`endif
endmodule
