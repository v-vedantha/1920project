
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

function LineIndex getSlot(CacheAddr addr);
    return truncate(addr);
endfunction

function CacheTag getTag(CacheAddr addr);
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
            if ((state.tag == getTag(req.addr) && (!isCompatible(state.msi, req.state) && !state.waitc))) begin
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
            if (state.waitc)
                ret = False;
        end
        if (fromInteger(i) != req.child) begin
            // If the section is Valid and the state is not compatible and the addresses match
            if ((state.tag == getTag(req.addr) && (!isCompatible(state.msi, req.state) && !state.waitc))) begin
                ret = False;
            end
        end
    end
    return ret;
endfunction

module mkPPP(MessageGet c2m, MessagePut m2c, WideMem mem, Empty ifc);
    Vector#(CoreNum, Vector#(CacheRows, Reg#(DirData))) childState <- replicateM(replicateM(mkReg(DirData{msi: I, waitc: False, tag: ?})));

    rule respond if (c2m.hasReq);
        CacheMemReq req = c2m.first().Req;
        let slot = getSlot(req.addr);
        let statea = childState[req.child][slot];

        if (isOkToRespond(childState, req)) begin
            let d = (statea.msi == I) ? statea.data : ?; // Where the req to mem should happen
            m2c.enq_resp(CacheMemResp{child: req.child, addr: req.addr, state: req.state, data: d});
            statea.msi <= req.state;
            c2m.deq;
        end
    endrule

    rule downgrade if (c2m.hasReq);
        CacheMemReq req = c2m.first().Req;
        LineIndex slot = getSlot(req.addr);
        let statea = childState[slot];
        MSI y = req.state;
        Maybe#(CoreID) maybechild = findChildToDown(childState, req);
        if (maybechild matches tagged Valid .child) begin
            childState[child][slot].waitc <= True;
            m2c.enq_req(CacheMemReq{child: child,
                addr: req.addr, 
                state: (y==M ? I : S)});
        end
    endrule

    rule recvResponse if (c2m.hasResp);
        CacheMemResp resp = c2m.first().Resp;
        let slot = getSlot(resp.addr);
        let statea = childState[resp.child][slot];
        if (statea.msi == M)
            statea.data <= resp.data; // Where the mem should be written to

        childState[resp.child][slot].waitc <= False;
        childState[resp.child][slot].msi <= resp.state;
    endrule

endmodule

    