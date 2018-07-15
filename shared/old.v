module yarvi( input  wire        clock
            , input  wire        reset

            , output reg  [61:0] address
            , output reg         writeenable = 0
            , output reg  [63:0] writedata
            , output reg  [ 7:0] byteena
            , output reg         readenable = 0
            , input  wire [63:0] readdata

            , output wire        bus_req_ready
            , input  wire        dc_fill_we
            , input  wire [63:0] dc_fill_addr
            , input  wire [63:0] dc_fill_data

            , input  wire [11:0] bus_csr_addr
            , input  wire        bus_csr_read_enable
            , input  wire        bus_csr_write_enable
            , input  wire [63:0] bus_csr_writedata
            , output reg  [63:0] bus_csr_readdata
            , output reg         bus_csr_readdata_valid = 0
            );

   /* Global state */

   /* CPU state.  These are a special-case of pipeline registers.  As
      they are only (and must only be) written by the EX stage, we
      needn't keeps per-stage versions of these.

      Note, a pipelined implementation will necessarily have access to
      the up-to-date version of the state, thus care must be taken to
      forward the correct valid where possible and restart whenever
      the use of an out-of-date value is detected.  In the cases where
      the update is rare it's likely better to unconditionally restart
      the pipeline whenever the update occurs (eg. writes of
      csr_satp).

      Exceptions to this are CSR mcycle and mtime which are
      generally updated independent of what happens in the
      pipeline. */

   reg  [63:0] regs[0:31];

   // All CSRs can be accessed by csrXX instructions, but some are
   // used directly by the pipeline, as annotated below.

   // URW
   reg  [ 4:0] csr_fflags       = 0;
   reg  [ 2:0] csr_frm          = 0;

`ifdef not_used
   // MRO, Machine Information Registers
   reg  [63:0] csr_mvendorid    = 0;
   reg  [63:0] csr_marchid      = 0;
   reg  [63:0] csr_mimpid       = 0;
   reg  [63:0] csr_mhartid      = 0;
`endif

   // MRW, Machine Trap Setup
   reg  [63:0] csr_mstatus      = {2'd 3, 1'd 0};
   reg  [ 7:0] csr_mie          = 0;
   reg  [63:0] csr_mtvec        = 'h 100;

   // MRW, Machine Time and Counters
   // MRW, Machine Trap Handling
   reg  [63:0] csr_mscratch     = 0;
   reg  [63:0] csr_mepc         = 0;
   reg  [63:0] csr_mcause       = 0;
   reg  [63:0] csr_mtval        = 0;
   reg  [ 7:0] csr_mip          = 0;

   // URO
   reg  [63:0] csr_mcycle       = 0;
   reg  [63:0] csr_mtime        = 0;
   reg  [63:0] csr_minstret     = 0;

   // MRW, Machine Host-Target Interface (Non-Standard Berkeley Extension)
   reg  [63:0] htif_tohost      = 0;
   reg  [63:0] htif_fromhost    = 0;

   /* So far we only support M mode */
   wire [63:0] pending_ints     = csr_mstatus`MIE ? csr_mie & csr_mip : 0;
   reg  [ 2:0] interrupt_cause;
   always @(*)
     if      (pending_ints[0]) interrupt_cause = 0;
     else if (pending_ints[1]) interrupt_cause = 1;
     else if (pending_ints[2]) interrupt_cause = 2;
     else if (pending_ints[3]) interrupt_cause = 3;
     else if (pending_ints[4]) interrupt_cause = 4;
     else if (pending_ints[5]) interrupt_cause = 5;
     else if (pending_ints[6]) interrupt_cause = 6;
     else interrupt_cause = 7;

   wire        interrupt = 0;

   /* Forward declarations */
   reg         ex_restart          = 1;
   reg  [63:0] ex_next_pc          = `INIT_PC;
   reg         ex_valid_           = 0;
   wire        ex_valid            = ex_valid_;
   reg  [31:0] ex_inst;
   reg         ex_wben;
   reg  [63:0] ex_wbv;

   reg         wb_valid            = 0;
   reg  [31:0] wb_inst;
   reg         wb_wben;
   reg  [63:0] wb_wbv;

//// INSTRUCTION FETCH ////

   reg         if_valid_           = 0;
   wire        if_valid            = if_valid_ && !ex_restart;
   reg  [63:0] if_pc               = 0;

   always @(posedge clock) begin
      if_valid_ <= if_valid || ex_restart;
      if_pc     <= ex_next_pc;
   end

   wire [31:0] if_inst;

//// DECODE AND REGISTER FETCH ////

   /* If the previous cycle restarted the pipeline then this
      invalidates this stage, eg.

       IF       DE       EX
       8:sw     4:br     0:br 20  --> restart from 20
       20:add   8:-      4:-
       ...      20:add   8:-
       ...      ...      20:add

    */

   reg         de_valid_ = 0;
   wire        de_valid = de_valid_ && !ex_restart;
   reg  [63:0] de_pc;
   reg  [31:0] de_inst;
   // XXX Not entirely sure that's correct
   wire        de_illegal_csr_access = de_valid &&
               de_insn`opcode == `SYSTEM        &&
               de_insn`funct3 != `PRIV          &&
               (de_insn[31:30] == 3 &&
                (de_insn`funct3 != `CSRRS || de_insn`rs1 != 0));

   reg  [63:0] de_csr_val;

   always @(posedge clock) begin
      de_valid_ <= if_valid;
      de_pc     <= if_pc;
      de_inst   <= if_inst;
   end

   reg  [63:0] de_rs1_val_r;
   reg  [63:0] de_rs2_val_r;

   wire        de_rs1_forward_ex = de_insn`rs1 == ex_insn`rd && ex_wben;
   wire        de_rs2_forward_ex = de_insn`rs2 == ex_insn`rd && ex_wben;
   wire        de_rs1_forward_wb = de_insn`rs1 == wb_insn`rd && wb_wben;
   wire        de_rs2_forward_wb = de_insn`rs2 == wb_insn`rd && wb_wben;

   wire [63:0] de_rs1_val      = de_rs1_forward_ex ? ex_wbv :
                                 de_rs1_forward_wb ? wb_wbv : de_rs1_val_r;
   wire [63:0] de_rs2_val      = de_rs2_forward_ex ? ex_wbv :
                                 de_rs2_forward_wb ? wb_wbv : de_rs2_val_r;

   wire [63:0] de_rs1_val_cmp  = (~de_insn`br_unsigned << 63) ^ de_rs1_val;
   wire [63:0] de_rs2_val_cmp  = (~de_insn`br_unsigned << 63) ^ de_rs2_val;
   wire        de_cmp_eq       = de_rs1_val     == de_rs2_val;
   wire        de_cmp_lt       = de_rs1_val_cmp  < de_rs2_val_cmp;
   wire        de_branch_taken = (de_insn`br_rela ? de_cmp_lt : de_cmp_eq) ^ de_insn`br_negate;

   wire        de_sign         = de_insn[31];
   wire [51:0] de_sign52       = {52{de_sign}};
   wire [43:0] de_sign44       = {44{de_sign}};

   // I-type
   wire [63:0] de_i_imm        = {de_sign52, de_insn`funct7, de_insn`rs2};

   // S-type
   wire [63:0] de_s_imm        = {de_sign52, de_insn`funct7, de_insn`rd};
   wire [63:0] de_sb_imm       = {de_sign52, de_insn[7], de_insn[30:25], de_insn[11:8], 1'd0};

   // U-type
   wire [63:0] de_uj_imm       = {de_sign44, de_insn[19:12], de_insn[20], de_insn[30:21], 1'd0};

   wire [63:0] de_rs2_val_imm  = de_insn`opcode == `OP_IMM ? de_i_imm : de_rs2_val;

   wire [63:0] de_load_addr    = de_rs1_val + de_i_imm;
   wire [63:0] de_store_addr   = de_rs1_val + de_s_imm;
   wire [`DC_WORDS_LG2-1:0]
               de_load_wa      = de_load_addr[`DC_WORDS_LG2+1:2];
   wire [`DC_WORDS_LG2-1:0]
               de_store_wa     = de_store_addr[`DC_WORDS_LG2+1:2];
   wire [ 7:0] de_bytemask     = de_insn`funct3 == 0 || de_insn`funct3 == 4 ? 8'h  1:
                                 de_insn`funct3 == 1 || de_insn`funct3 == 5 ? 8'h  3:
                                 de_insn`funct3 == 2 || de_insn`funct3 == 6 ? 8'h  F:
                                                                              8'h FF;
   wire [ 7:0] de_load_byteena = de_bytemask << de_load_addr[3:0];
   wire [ 7:0] de_store_byteena= de_bytemask << de_store_addr[3:0];
   wire        de_store        = de_valid && de_insn`opcode == `STORE;
   wire        dc_we           = de_store &&
                                 de_store_addr[63:`DC_WORDS_LG2+2] == (`DATA_START >> (`DC_WORDS_LG2 + 2));
   wire        de_load         = de_valid && de_insn`opcode == `LOAD;
   wire [63:0] de_rs2_val_shl  = de_rs2_val << (de_store_addr[1:0]*8);

   reg [11:0] de_csrd;

   always @(*)
     case (de_insn`funct3)
     `CSRRS:  de_csrd = de_insn`rs1 ? de_insn`imm11_0 : 0;
     `CSRRC:  de_csrd = de_insn`imm11_0;
     `CSRRW:  de_csrd = de_insn`imm11_0;
     `CSRRSI: de_csrd = de_insn`imm11_0;
     `CSRRCI: de_csrd = de_insn`imm11_0;
     `CSRRWI: de_csrd = de_insn`imm11_0;
     default: de_csrd = 0;
     endcase

   always @(*)
     case (de_insn`imm11_0)
     `CSR_MSTATUS:      de_csr_val = csr_mstatus;
     `CSR_MISA:         de_csr_val = (2 << 30) | (1 << ("I"-"A"));
     `CSR_MIE:          de_csr_val = csr_mie;
     `CSR_MTVEC:        de_csr_val = csr_mtvec;

     `CSR_MSCRATCH:     de_csr_val = csr_mscratch;
     `CSR_MEPC:         de_csr_val = csr_mepc;
     `CSR_MCAUSE:       de_csr_val = csr_mcause;
     `CSR_MTVAL:        de_csr_val = csr_mtval;
     `CSR_MIP:          de_csr_val = csr_mip;

     `CSR_MCYCLE:       de_csr_val = csr_mcycle;
     `CSR_MINSTRET:     de_csr_val = csr_minstret;

     `CSR_FFLAGS:       de_csr_val = csr_fflags;
     `CSR_FRM:          de_csr_val = csr_frm;
     `CSR_FCSR:         de_csr_val = {csr_frm, csr_fflags};
     default:           de_csr_val = 0;
     endcase

   always @(posedge clock) begin
      case (bus_csr_addr)
        `CSR_MSTATUS:      bus_csr_readdata <= csr_mstatus;
        `CSR_MISA:         bus_csr_readdata <= (2 << 30) | (1 << ("I"-"A"));
        `CSR_MIE:          bus_csr_readdata <= csr_mie;
        `CSR_MTVEC:        bus_csr_readdata <= csr_mtvec;

        `CSR_MSCRATCH:     bus_csr_readdata <= csr_mscratch;
        `CSR_MEPC:         bus_csr_readdata <= csr_mepc;
        `CSR_MCAUSE:       bus_csr_readdata <= csr_mcause;
        `CSR_MTVAL:        bus_csr_readdata <= csr_mtval;
        `CSR_MIP:          bus_csr_readdata <= csr_mip;

        `CSR_MCYCLE:       bus_csr_readdata <= csr_mcycle;
        `CSR_MINSTRET:     bus_csr_readdata <= csr_minstret;

        `CSR_FFLAGS:       bus_csr_readdata <= csr_fflags;
        `CSR_FRM:          bus_csr_readdata <= csr_frm;
        `CSR_FCSR:         bus_csr_readdata <= {csr_frm, csr_fflags};
        default:           bus_csr_readdata <= 0;
      endcase
      bus_csr_readdata_valid <= bus_csr_read_enable;
   end

//// EXECUTE ////

   reg  [63:0] ex_load_addr;

   reg  [11:0] ex_csrd;
   reg  [63:0] ex_csr_res;
   reg  [ 3:0] ex_load_byteena;
   wire [63:0] dc_q;

//// WRITEBACK ////

   reg  [11:0] wb_csrd;

   always @(posedge clock) begin
      ex_valid_       <= de_valid & !de_illegal_csr_access;
      ex_inst         <= de_inst;
      ex_load_addr    <= de_load_addr;
      ex_csrd         <= de_csrd;
      ex_load_byteena <= de_load_byteena;
   end


   // XXX It would be easy to support unaligned memory
   // with this setup by just calculating a different de_load_wa for
   // every slice and rotate the loaded word rather than just shifting
   // it. Similar for store.  Of course, IO access must still be
   // aligned as well as atomics.
   wire [63:0] ex_ld = /* ex_load_addr[31] XXX is now broken ? readdata : */ dc_q;
   reg  [63:0] ex_ld_shifted, ex_ld_res;

   always @(*) begin
      ex_ld_shifted = ex_ld >> (ex_load_addr[1:0] * 8);
      case (ex_insn`funct3)
         0: ex_ld_res = {{24{ex_ld_shifted[ 7]}}, ex_ld_shifted[ 7:0]};
         1: ex_ld_res = {{16{ex_ld_shifted[15]}}, ex_ld_shifted[15:0]};
         4: ex_ld_res = ex_ld_shifted[ 7:0];
         5: ex_ld_res = ex_ld_shifted[15:0];
         default: ex_ld_res = ex_ld;
      endcase
   end

   // Note, this could be done in stage DE and thus give a pipelined
   // implementation a single cycle branch penalty

   always @(posedge clock) begin
      if (ex_restart)
         $display("%05d  RESTARTING FROM %x TO %x", $time, ex_pc, ex_next_pc);

      ex_restart    <= 0;
      ex_next_pc    <= ex_next_pc + 4;

      // Restart if the previous instruction wrote a CSR or was fence.i
      if (de_valid && (de_insn`opcode == `SYSTEM && de_csrd ||
                       de_insn`opcode == `MISC_MEM)) begin
         ex_restart <= 1;
         ex_next_pc <= de_pc + 4;
      end

      // Take Illegal instruction exception on illegal CSR access
      // XXX Centralize exception handling
      if (de_illegal_csr_access) begin
         ex_restart <= 1;
         ex_next_pc <= csr_mtvec;
      end

      case ({!de_valid & !interrupt, de_insn`opcode})
        `BRANCH:
          if (de_branch_taken) begin
             ex_restart    <= 1;
             ex_next_pc    <= de_pc + de_sb_imm;
          end
        `JALR: begin
           ex_restart    <= 1;
           ex_next_pc    <= (de_rs1_val + de_i_imm) & ~64'd1;
        end
        `JAL: begin
           ex_restart    <= 1;
           ex_next_pc    <= de_pc + de_uj_imm;
        end
        `SYSTEM: begin
           case (de_insn`funct3)
           `PRIV:
             begin
                ex_restart    <= 1;
                case (de_insn`imm11_0)
                  `ECALL: ex_next_pc <= csr_mtvec;
                  `MRET: begin
                     ex_next_pc      <= csr_mepc;
                     csr_mstatus`MIE <= csr_mstatus`MPIE;
                  end
                  `EBREAK: $finish; // XXX
                  default: begin
                     $display("NOT IMPLEMENTED SYSTEM.PRIV 0x%x (inst %x)",
                              de_insn`imm11_0, de_inst);
                     $finish;
                  end
                endcase
             end
           endcase
           end
      endcase

      // Interrupts
      if (interrupt) begin
        ex_restart    <= 1;
        ex_next_pc    <= csr_mtvec;
      end

      if (reset) begin
         ex_restart   <= 1;
         ex_next_pc   <= `INIT_PC;
      end
   end

   // XXX This violates the code style above but is trivial to fix
   reg  [63:0] ex_res;
   always @(posedge clock)
      case (de_insn`opcode)
         `OP_IMM, `OP:
            case (de_insn`funct3)
            `ADDSUB: if (de_insn[30] && de_insn`opcode == `OP)
                        ex_res <= de_rs1_val - de_rs2_val_imm;
                    else
                        ex_res <= de_rs1_val + de_rs2_val_imm;
            `SLL:  ex_res <= de_rs1_val << de_rs2_val_imm[4:0];
            `SLT:  ex_res <= $signed(de_rs1_val) < $signed(de_rs2_val_imm); // flip MSB of both operands
            `SLTU: ex_res <= de_rs1_val < de_rs2_val_imm;
            `XOR:  ex_res <= de_rs1_val ^ de_rs2_val_imm;
            `SR_:  if (de_insn[30])
                      ex_res <= $signed(de_rs1_val) >>> de_rs2_val_imm[4:0];
                   else
                      ex_res <= de_rs1_val >> de_rs2_val_imm[4:0];
            `OR:   ex_res <= de_rs1_val | de_rs2_val_imm;
            `AND:  ex_res <= de_rs1_val & de_rs2_val_imm;
          endcase

         `LUI:     ex_res <=         {de_insn[31:12], 12'd0};
         `AUIPC:   ex_res <= de_pc + {de_insn[31:12], 12'd0};

         `JALR:    ex_res <= de_pc + 4;
         `JAL:     ex_res <= de_pc + 4;

         `SYSTEM:
            case (de_insn`funct3)
            `CSRRS:  begin ex_res <= de_csr_val; ex_csr_res <= de_csr_val |  de_rs1_val; end
            `CSRRC:  begin ex_res <= de_csr_val; ex_csr_res <= de_csr_val &~ de_rs1_val; end
            `CSRRW:  begin ex_res <= de_csr_val; ex_csr_res <=               de_rs1_val; end
            `CSRRSI: begin ex_res <= de_csr_val; ex_csr_res <= de_csr_val |  de_insn`rs1; end
            `CSRRCI: begin ex_res <= de_csr_val; ex_csr_res <= de_csr_val &~ de_insn`rs1; end
            `CSRRWI: begin ex_res <= de_csr_val; ex_csr_res <=               de_insn`rs1; end
            endcase
      endcase

//// WRITE BACK ////

   always @(*) ex_wbv = ex_insn`opcode == `LOAD ? ex_ld_res : ex_res;
   always @(*) ex_wben = ex_valid && ex_insn`rd &&
                         ex_insn`opcode != `BRANCH && ex_insn`opcode != `STORE;

   always @(posedge clock) begin
      if (ex_wben)
         regs[ex_insn`rd] <= ex_wbv;
      de_rs1_val_r <= regs[if_insn`rs1];
      de_rs2_val_r <= regs[if_insn`rs2];
   end

   always @(posedge clock) begin
      wb_valid <= ex_valid;
      wb_inst <= ex_inst;
      wb_wben <= ex_wben;
      wb_wbv  <= ex_wbv;
      wb_csrd <= ex_csrd;
   end

   always @(posedge clock) begin
      csr_mcycle   <= csr_mcycle + 1;
      csr_mtime    <= csr_mtime  + 1;
      csr_minstret <= csr_minstret + ex_valid;

      //// CSR updates ////

      if (de_illegal_csr_access)
        $display("%05d  exception: illegal CSR access attempted %x %x (priviledge %d, CSR %x)",
                 $time, de_pc, de_inst, 3, de_insn`imm11_0);

      if (ex_valid & !interrupt) begin
         if (ex_csrd && ex_insn`opcode == `SYSTEM)
           begin
           $display("          CSR%x <- %x", ex_csrd, ex_csr_res);

           case (ex_csrd)
           `CSR_FFLAGS:    csr_fflags           <= ex_csr_res;
           `CSR_FRM:       csr_frm              <= ex_csr_res;
           `CSR_FCSR:      {csr_frm,csr_fflags} <= ex_csr_res;

           `CSR_MSTATUS:   csr_mstatus          <= ex_csr_res & ~(15 << 12); // No FP or XS;
           `CSR_MIE:       csr_mie              <= ex_csr_res;
//         `CSR_MTIMECMP:  csr_mtimecmp         <= ex_csr_res; XXX ??

           `CSR_MSCRATCH:  csr_mscratch         <= ex_csr_res;
           `CSR_MEPC:      csr_mepc             <= ex_csr_res;
           `CSR_MIP:       csr_mip[3]           <= ex_csr_res[3];
           `CSR_MTVEC:     csr_mtvec            <= ex_csr_res;
           default:
             $display("warning: writing an unimplemented CSR");
           endcase
           end
      end

      // NB: We delay the interrupt until the instruction is valid to avoid
      // complications in computing csr_mepc.  This works as long as ex_valid
      // will eventuall be set, which is _currently_ true.

      if (de_valid &&
          (pending_ints != 0 ||
           de_insn`opcode == `SYSTEM &&
           de_insn`funct3 == `PRIV &&
           de_i_imm[11:0] != `MRET) ||
          de_illegal_csr_access) begin

          csr_mepc          <= de_pc;
          csr_mstatus[11:3] <= csr_mstatus[8:0];         // PUSH
          csr_mstatus`MPIE  <= csr_mstatus`MIE;
          csr_mstatus`MIE   <= 0;
          csr_mcause[31]    <= interrupt;
          csr_mcause[30:0]  <= interrupt                 ? interrupt_cause    :
                               de_illegal_csr_access     ? `TRAP_INST_ILLEGAL :
                               de_i_imm[11:0] == `EBREAK ? `TRAP_BREAKPOINT   :
                                                           `TRAP_ECALL_MMODE;
      end

    end

//// MEMORY ACCESS ////

   wire [`DC_WORDS_LG2-1:0] dc_addr = dc_we ? de_store_wa : de_load_wa;
   wire [63:0]              dc_d = de_rs2_val_shl;


   // XXX A store followed immediately by a load overlapping what was
   // stored will return the wrong data.  We _could_ forward the data
   // for the cases where the loaded data completely covers what was
   // loaded, but it would likely incur a cycle time penalty for this
   // extremely rare situation and it wouldn't help cases where
   // there's only a partial overlap.  Instead we should detect this
   // load-hit-store hazard and restart the load.  This still needs to
   // be done!
   bram_tdp #(32, `DC_WORDS_LG2, `INIT_MEM) code_mem
     ( .a_clk	(clock)
     , .a_wr	(writeenable)
     , .a_addr  (address)
     , .a_din   (writeenable)
     , .a_dout  ()

     , .b_clk	(clock)
     , .b_wr	(0)
     , .b_addr  (ex_next_pc[`DC_WORDS_LG2+1:2])
     , .b_din   ('hx)
     , .b_dout  (if_inst));


   /* Directly mapped D$ */

   genvar i;
   generate
      for (i = 0; i < 8 ; i = i + 1) begin : dc_data_gen
         bram_tdp #(8, `DC_WORDS_LG2, "") dc_byte_slice
               ( .a_clk		(clock)
               , .a_wr		(dc_fill_we)
               , .a_addr  	(dc_fill_address)
               , .a_din   	(dc_fill_data[i*8+7:i*8])

               , .b_clk		(clock)
               , .b_wr		(dc_we && de_store_byteena[i])
               , .b_addr	(dc_addr)
               , .b_din		(dc_d[i*8+7:i*8])
               , .b_dout	(dc_q[i*8+7:i*8]));

      end
   endgenerate

   bram_tdp #(8, `DC_WORDS_LG2, "") dc_tags
     ( .a_clk		(clock)
       , .a_wr		(dc_fill_tag_we)
       , .a_addr  	(dc_fill_tag_address)
       , .a_din   	(dc_fill_tag_data)

       , .b_clk		(clock)
       , .b_addr	(dc_addr)
       , .b_din		(dc_d[i*8+7:i*8])
       , .b_dout	(dc_q[i*8+7:i*8]));



   always @(*) begin
     writedata   = de_rs2_val_shl;
     byteena     = de_store ? de_store_byteena : de_load_byteena;
     writeenable = de_store;
     readenable  = de_valid && de_insn`opcode == `LOAD && de_load_addr[63];
     address     = (de_store ? de_store_addr : de_load_addr) >> 3;
   end

   assign bus_req_ready = !de_load && !de_store;
   reg dc_q_is_bus_res = 0;
   always @(posedge clock) begin
      dc_q_is_bus_res <= bus_req_read_go;
      bus_res_valid             <= dc_q_is_bus_res;
      bus_res_data              <= dc_q;
   end

   initial $readmemh({`INITDIR,"initregs.txt"}, regs);

`ifdef VERBOSE_SIMULATION
   reg  [63:0] ex_pc, ex_sb_imm, ex_i_imm, ex_s_imm, ex_uj_imm;

   always @(posedge clock) begin
      ex_pc        <= de_pc;
      ex_sb_imm    <= de_sb_imm;
      ex_i_imm     <= de_i_imm;
      ex_s_imm     <= de_s_imm;
      ex_uj_imm    <= de_uj_imm;
   end

   always @(posedge clock)
      if (de_valid)
        case (de_insn`opcode)
        `LOAD: if (/*!de_load_addr[31] &&*/
                   de_load_addr[31:`DC_WORDS_LG2+2] != (`DATA_START >> (`DC_WORDS_LG2 + 2)))
                   $display("%05d  LOAD from %x is outside mapped memory (%x)", $time,
                            de_load_addr, de_load_addr[28:`DC_WORDS_LG2]);
        `STORE:
               if (de_store_addr[31:`DC_WORDS_LG2+2] != (`DATA_START >> (`DC_WORDS_LG2 + 2)))
                   $display("%05d  STORE to %x is outside mapped memory (%x != %x)", $time,
                            de_store_addr,
                            de_store_addr[31:`DC_WORDS_LG2+2], (`DATA_START >> (`DC_WORDS_LG2 + 2)));
        endcase

   always @(posedge clock) begin
`ifdef SIMULATION_VERBOSE_PIPELINE
      $display("");
      if (ex_restart)
        $display("%05d  RESTART", $time);
      $display("%05d  IF @ %x V %d", $time, if_pc, if_valid);
      $display("%05d  DE @ %x V %d (%d %d)", $time, de_pc, de_valid, de_valid_, ex_restart);
      $display("%05d  EX @ %x V %d %x", $time, ex_pc, ex_valid, ex_inst);
`endif


      if (ex_valid && ex_insn`rd && ex_insn`opcode != `BRANCH && ex_insn`opcode != `STORE)
         $display("%05d                                            x%1d <- 0x%x/%x", $time,
                  ex_insn`rd, ex_insn`opcode == `LOAD ? ex_ld_res : ex_res,
                  ex_load_byteena);
   end

   always @(posedge clock)
     if (dc_we)
         $display("%05d                                            [%x] <- %x/%x", $time, de_store_addr, de_rs2_val_shl, de_store_byteena);
`endif
endmodule
