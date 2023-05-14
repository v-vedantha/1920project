
import RegFile::*;
import StmtFSM::*;
import Vector::*;

import FIFO::*;
import FIFOF::*;
import MemTypes::*;
import SpecialFIFOs::*;
import MessageFifo::*;
import MessageRouter::*;
import CoherencyTypes::*;
import PPP::*;
import BRAM::*;

module mkWideMem(WideMem);
    Reg#(Line) rf <- mkReg(unpack(0));
    FIFOF#(Line) respQ <- mkFIFOF;
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "memlines.vmh";
    BRAM1Port#(LineAddr, PackedLine) bram <- mkBRAM1Server(cfg);
    rule addToRespQ;
        let resp <- bram.portA.response.get();
        respQ.enq(unpack(resp));
    endrule

    method Action req(WideMemReq r);
        bram.portA.request.put(BRAMRequest{
            write: (r.write_en != 0),
            responseOnWrite: False,
            address: r.addr,
            datain: pack(r.data)
            });
    endmethod
    method ActionValue#(Line) resp;
        $display("Sending", fshow(respQ.first));
        respQ.deq;
        return respQ.first;
    endmethod
	method Bool respValid = respQ.notEmpty;
endmodule
