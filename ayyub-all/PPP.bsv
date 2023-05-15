
import CoherencyTypes::*;
import MessageFifo::*;
import MessageRouter::*;
import MemTypes::*;
import Vector::*;

typedef struct {
    MSI msi;
    Bool waitc;
    CacheTag tag;
    // Line data;
} DirData deriving(Eq,Bits,FShow);

typedef 128 CacheRows;

function Bool isCompatible(MSI a, MSI b);
    return (a == S && b == S) || (a == I) || (b == I);
endfunction

function LineIndex getSlot(LineAddr addr);
    return truncate(addr);
endfunction

function CacheTag getTag(LineAddr addr);
    return truncate(addr >> valueOf(NumCacheLineBits));
endfunction

function Maybe#(CoreID) findChildToDown(Vector#(CoreNum, Vector#(CacheRows, Reg#(DirData))) dirData,
        CacheMemReq req);

    // Logic is kind of annoying
    let slot = getSlot(req.addr);
    Maybe#(CoreID) ret = tagged Invalid;

    for (Integer i = 0; i < valueOf(CoreNum); i = i + 1) begin
        if (fromInteger(i) != req.child) begin
            DirData state = dirData[i][slot];
            // If the section is Valid and the state is not compatible and the addresses match
            if (state.tag == getTag(req.addr) && !isCompatible(state.msi, req.state) && !state.waitc) begin
                ret = tagged Valid fromInteger(i);
            end
        end
    end
    return ret;
endfunction

function Bool isOkToRespond(Vector#(CoreNum, Vector#(CacheRows, Reg#(DirData))) dirData,
        CacheMemReq req);

    // Logic is kind of annoying
    let slot = getSlot(req.addr);
    Bool ret = True;

    for (Integer i = 0; i < valueOf(CoreNum); i = i + 1) begin
        DirData state = dirData[i][slot];
        if (req.child == fromInteger(i)) begin
            if (state.waitc) begin
                ret = False;
            end
        end
        if (fromInteger(i) != req.child) begin
            // If the section is Valid and the state is not compatible and the addresses match
            if (state.tag == getTag(req.addr) && !isCompatible(state.msi, req.state)) begin
                ret = False;
            end
        end
    end
    return ret;
endfunction

module mkPPP(MessageGet c2m, MessagePut m2c, WideMem mem, Empty ifc);
    Vector#(CoreNum, Vector#(CacheRows, Reg#(DirData))) childState <- replicateM(replicateM(mkReg(DirData{msi: I, waitc: False, tag: ?})));
    Reg#(CacheMemReq) currentReq <- mkReg(CacheMemReq{child: 0, addr: 0, state: I});
    Reg#(Bool) busy <- mkReg(False);
    Reg#(Bool) tryDowngrade <- mkReg(False);
    Bool debug = False;
    
    rule respond if (c2m.hasReq && !c2m.hasResp && !busy && !tryDowngrade);
        CacheMemReq req = c2m.first().Req;
        currentReq <= req;
        let slot = getSlot(req.addr);
        let statea = childState[req.child][slot];
        if (debug) $display("Respond 1 to ", fshow(req));

        if (isOkToRespond(childState, req)) begin
            busy <= True;
            if (debug) $display("Reading from memory");
            mem.req(WideMemReq{
                write_en: fromInteger(0),
                addr: req.addr,
                data: ?
            });
            c2m.deq;
        end
        else begin
            if (debug) $display("downgrade start");
            tryDowngrade <= True;
        end
    endrule

    rule respond2 if (busy);
        if (debug) $display("Respond 2");
        busy <= False;
        Line data <- mem.resp();
        CacheMemReq req = currentReq;
        let slot = getSlot(req.addr);
        let statea = childState[req.child][slot];
        let d = (statea.msi == I) ? tagged Valid (data) : tagged Invalid;
        m2c.enq_resp(CacheMemResp{child: req.child, addr: req.addr, state: req.state, data: d});
        childState[req.child][slot] <= DirData{
            msi: req.state,
            waitc: childState[req.child][slot].waitc,
            tag: getTag(req.addr)
        };
        // childState[req.child][slot].msi <= req.state;
        // statea.msi <= req.state;
    endrule

    rule downgrade if (!c2m.hasResp && tryDowngrade);
        tryDowngrade <= False;
        CacheMemReq req = currentReq;
        if (debug) $display("downgrade for ", fshow(req));
        LineIndex slot = getSlot(req.addr);
        let statea = childState[req.child][slot];
        MSI y = req.state;
        Maybe#(CoreID) maybechild = findChildToDown(childState, req);
        if (maybechild matches tagged Valid .child) begin
            if (debug) $display("ok removed something");
            childState[child][slot].waitc <= True;
            m2c.enq_req(CacheMemReq{child: child,
                addr: req.addr, 
                state: (y==M ? I : S)});
        end
    endrule

    rule recvResponse if (c2m.hasResp);
        CacheMemResp resp = c2m.first().Resp;
        if (debug) $display("response to respo", fshow(resp));
        c2m.deq;
        let slot = getSlot(resp.addr);
        let statea = childState[resp.child][slot];
        if (statea.msi == M) begin
            if (debug) $display("Wrote to memory");
            mem.req(WideMemReq{
                write_en: signExtend(1'b1),
                addr: resp.addr,
                data: resp.data.Valid
            });
        end

        // childState[resp.child][slot].waitc <= False;
        childState[resp.child][slot] <= DirData{
            msi: resp.state,
            waitc: False,
            tag: childState[resp.child][slot].tag
        };
        // }.msi <= resp.state;
    endrule

endmodule

    