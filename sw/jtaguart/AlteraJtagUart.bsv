import FIFOF::*;
import GetPut::*;
export GetPut::*;

export JtagWord(..);
export AlteraJtagUart(..);
export mkAlteraJtagUart;

typedef Bit#(8) JtagWord;

interface AltJtagAtlantic;
    method Bool can_write_next_cycle();
    method Action write(JtagWord data);
    method Action ask_read();
    method JtagWord read();
endinterface

import "BVI" alt_jtag_atlantic =
    module mkAltJtagAtlantic#(Integer log2rx, Integer log2tx) (AltJtagAtlantic);
        parameter INSTANCE_ID = 0;
        // the parameters below use the inverse notation of ours
        parameter LOG2_RXFIFO_DEPTH = log2tx;  // from HW to JTAG
        parameter LOG2_TXFIFO_DEPTH = log2rx;  // from JTAG to HW
        parameter SLD_AUTO_INSTANCE_INDEX = "YES";
        
        method r_ena can_write_next_cycle();
        method write(r_dat) enable(r_val);
        method ask_read() enable(t_dav);
        method t_dat read() ready(t_ena);

        default_clock clk(clk, (*unused*)GATE);
        default_reset rst(rst_n);

        schedule (can_write_next_cycle) CF (write);
        schedule (can_write_next_cycle) CF (ask_read);
        schedule (can_write_next_cycle) CF (read);
        schedule (can_write_next_cycle) CF (can_write_next_cycle);
        schedule (write) CF (read);
        schedule (write) CF (ask_read);
        schedule (write) C (write);
        schedule (ask_read) C (ask_read);
        schedule (ask_read) CF (read);
        schedule (read) CF (read);
    endmodule

interface AlteraJtagUart;
    interface Put#(JtagWord) tx;
    interface Get#(JtagWord) rx;
endinterface

module mkAlteraJtagUart#(Integer log2rx, Integer log2tx) (AlteraJtagUart);
    AltJtagAtlantic atlantic <- mkAltJtagAtlantic(log2rx, log2tx);
    FIFOF#(JtagWord) rxfifo <- mkSizedFIFOF(2**log2rx);
    FIFOF#(JtagWord) txfifo <- mkSizedFIFOF(2**log2tx);
    Reg#(Bool) can_tx <- mkReg(False);

    rule ask_tx;
        can_tx <= atlantic.can_write_next_cycle;
    endrule
    rule do_tx(can_tx);
        atlantic.write(txfifo.first);
        txfifo.deq;
    endrule
    rule ask_rx(rxfifo.notFull);
        atlantic.ask_read();
    endrule
    rule do_rx;
        rxfifo.enq(atlantic.read());
    endrule

    interface Put tx = toPut(txfifo);
    interface Get rx = toGet(rxfifo);
endmodule
