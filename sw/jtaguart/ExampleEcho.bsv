import AlteraJtagUart::*;
import Connectable::*;

(* synthesize *)
module mkExampleEcho(Empty);
    AlteraJtagUart uart <- mkAlteraJtagUart(6, 6);
    mkConnection(uart.tx, uart.rx);
endmodule
