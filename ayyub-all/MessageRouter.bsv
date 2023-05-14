import Vector::*;
// import CacheTypes::*;
import CoherencyTypes::*;
import MessageFifo::*;
// import Types::*;

interface MessageGet;
  method Bool hasResp;
  method Bool hasReq;
  method Bool notEmpty;
  method CacheMemMessage first;
  method Action deq;
endinterface
interface MessagePut;
    method Action enq_req(CacheMemReq d);
    method Action enq_resp(CacheMemResp d);
endinterface

function MessagePut toMessagePut(MessageFifo#(n) ifc);
	return (interface MessagePut;
		method enq_resp = ifc.enq_resp;
		method enq_req = ifc.enq_req;
	endinterface);
endfunction

function MessageGet toMessageGet(MessageFifo#(n) ifc);
	return (interface MessageGet;
		method hasResp = ifc.hasResp;
		method hasReq = ifc.hasReq;
		method notEmpty = ifc.notEmpty;
		method first = ifc.first;
		method deq = ifc.deq;
	endinterface);
endfunction


module mkMessageRouter(
  Vector#(CoreNum, MessageGet) c2r, Vector#(CoreNum, MessagePut) r2c, 
  MessageGet m2r, MessagePut r2m,
  Empty ifc 
);
    Reg#(CoreID) nextCoreInput <- mkReg(0);
    Reg#(CoreID) nextCoreOutput <- mkReg(0);
    rule tick;
        CoreIDPlusOne result = zeroExtend(nextCoreInput + 1);
        nextCoreInput <= truncate(result % fromInteger(valueOf(CoreNum)));
    endrule

    rule addToM;
        MessageGet m = c2r[nextCoreInput];
        let firstMessage = m.first();
        if (m.hasResp) begin
            r2m.enq_resp(firstMessage.Resp);
            c2r[nextCoreInput].deq();
        end else if (m.hasReq) begin
            r2m.enq_req(firstMessage.Req);
            c2r[nextCoreInput].deq();
        end
    endrule

    rule addToC;
        CacheMemMessage m = m2r.first();
        if (m2r.hasResp()) begin
            r2c[m.Resp.child].enq_resp(m.Resp);
            m2r.deq();
        end else if (m2r.hasReq()) begin
            r2c[m.Req.child].enq_req(m.Req);
            m2r.deq();
        end
    endrule
endmodule
