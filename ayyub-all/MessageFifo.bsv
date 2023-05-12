import FIFO::*;
import FIFOF::*;
// import Ehr::*;
import MemTypes::*;
import BRAM::*;
import Vector::*;
import CoherencyTypes::*;

typedef struct{
    CoreID            child;
    CacheAddr              addr;
    MSI               state;
    Maybe#(Line) data;
} CacheMemResp deriving(Eq, Bits, FShow);
typedef struct{
    CoreID      child;
    CacheAddr        addr;
    MSI         state;
} CacheMemReq deriving(Eq, Bits, FShow);
typedef union tagged {
    CacheMemReq     Req;
    CacheMemResp    Resp;
} CacheMemMessage deriving(Eq, Bits, FShow);

interface MessageFifo#(numeric type n);
  method Action enq_resp(CacheMemResp d);
  method Action enq_req(CacheMemReq d);
  method Bool hasResp;
  method Bool hasReq;
  method Bool notEmpty;
  method CacheMemMessage first;
  method Action deq;
endinterface


module mkMessageFifo(MessageFifo#(n));

    FIFOF#(CacheMemResp) responses <- mkFIFOF;
    FIFOF#(CacheMemReq) requests <- mkFIFOF;

    method Action enq_resp(CacheMemResp d);
        responses.enq(d);
    endmethod

    method Action enq_req(CacheMemReq d);
        requests.enq(d);
    endmethod

    method Bool hasResp;
        return responses.notEmpty();
    endmethod

    method Bool hasReq;
        return requests.notEmpty();
    endmethod

    method Bool notEmpty;
        return responses.notEmpty() || requests.notEmpty();
    endmethod

    method CacheMemMessage first if (responses.notEmpty() || requests.notEmpty());
        CacheMemMessage m = ?;
        if (responses.notEmpty()) begin
            m = tagged Resp (responses.first());
        end
        else if (requests.notEmpty()) begin
            m =  tagged Req ( requests.first());
        end
        return m;
    endmethod

    method Action deq;
        if (responses.notEmpty) begin
            responses.deq();
        end
        else begin
            requests.deq();
        end
    endmethod
endmodule
