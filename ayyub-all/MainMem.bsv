import Vector::*;
import RVUtil::*;
import BRAM::*;
import FIFO::*;
import SpecialFIFOs::*;
import DelayLine::*;
import MemTypes::*;
import CoherencyTypes::*;
import Cache::*;

typedef Bit#(512) PackedLine;
interface MainMem;
    method Action putI(MainMemReq req);
    method ActionValue#(MainMemResp) getI();
    method Action putRequest(CoherencyMessage message);
    method Action putResponse(CoherencyMessage message);
    method ActionValue#(CoherencyMessage) getRequest();
endinterface

typedef struct {
    Bool valid;
    Vector#(2, MSI) msis;
    Vector#(2, Bool) waitc;
} DirData deriving(Bits, Eq, FShow);

typedef struct {
    Bit#(512) data;
    DirData dirdata;
} MainMemResp deriving(Bits, Eq, FShow);

interface MainMemRef;
    method Action put(CacheReq req);
    method ActionValue#(Word) get();
endinterface

module mkMainMemFast(MainMemRef);
    BRAM_Configure cfg = defaultValue();
    BRAM1Port#(Bit#(30), Word) bram <- mkBRAM1Server(cfg);
    DelayLine#(1, Word) dl <- mkDL(); // Delay by 20 cycles

    rule deq;
        let r <- bram.portA.response.get();
        dl.put(r);
    endrule    

    method Action put(CacheReq req);
        // req.addr = req.addr[31:2];
        bram.portA.request.put(BRAMRequest{
                    write: unpack(req.write),
                    responseOnWrite: False,
                    address: req.addr[31:2],
                    datain: req.data});
    endmethod

    method ActionValue#(Word) get();
        let r <- dl.get();
        return r;
    endmethod
endmodule


// function DirAddr getSlot(CoherencyMessage message);
//     // Figure this out once we get cache fully done

//     return something;
// endfunction

function Bool isCompatible(MSI m1, MSI m2);
    return (m1 == I) || (m2 == I) || (m1 == S && m2 == S);
endfunction

function Bit#(1) findChildToDown(MainMemResp resp, CoherencyMessage message);
    Bit#(1) which = message.whichcache;
    for (Integer i = 0; i <= 1; i = i + 1) begin
        if (fromInteger(i) != message.whichcache) begin
            if (!isCompatible(message.msi, resp.dirdata.msis[i])) begin
                which = fromInteger(i);
            end
        end
    end
    return which;
endfunction 

// typedef enum {
//      ProcessingResponse 
// } ProcesserState deriving (Eq, FShow, Bits);
module mkMainMem(MainMem);
    BRAM_Configure cfg = defaultValue();
    BRAM2Port#(LineAddr, PackedLine) bram <- mkBRAM2Server(cfg);
    BRAM2Port#(LineAddr, DirData) dir <- mkBRAM2Server(cfg);
    // DelayLine#(40, PackedLine) dl <- mkDL(); // Delay by 20 cycles

    FIFO#(CoherencyMessage) incomingRequests <- mkFIFO;
    FIFO#(CoherencyMessage) incomingResponses <- mkFIFO;
    FIFO#(CoherencyMessage) outgoingMessages <- mkFIFO;

    Reg#(MainMemResp) currentlyResponse <- mkRegU;
    Reg#(CoherencyMessage) currentlyCM <- mkRegU;
    Reg#(Bool) currentlyWorking <- mkReg(False);

    Reg#(Bool) waitingForRequest <- mkReg(False);
    Reg#(Bool) waitingForIsOk <- mkReg(False);
    Reg#(Bool) waitingForDowngrade1 <- mkReg(False);
    Reg#(Bool) waitingForDowngrade2 <- mkReg(False);

    Reg#(MainMemResp) downgradeResponse <- mkRegU;
    Reg#(CoherencyMessage) downgradeCM <- mkRegU;
    Reg#(Bool) readt <- mkReg(False);
    
    Reg#(Bool) shoulWork <- mkReg(False);

    rule parentDowngrade if (!waitingForIsOk && currentlyWorking);
        // let slot <- getSlot(currentlyCM);
        let child = findChildToDown(currentlyResponse, currentlyCM);
        let y = currentlyCM.msi;
        if (child != currentlyCM.whichcache) begin
            currentlyResponse[child].waitc <= True;
            let downgradeRequest = CoherencyMessage{
                addr: currentlyCM.addr,
                msi: (y == M) ? I : S,
                whichcache: child,
                reqres: Request,
                data: currentlyResponse.data};
            outgoingMessages.enq(downgradeRequest);
        end
        waitingforIsOk <= True;
    endrule

    rule parentRespondsTo if (ready && !waitingForDowngrade1);
        let req <- incomingRequests.first();
        waitingForRequest <= True;
        currentlyCM <= req;
        currentlyWorking <= True;
        // let slot <- getSlot(request);
        bram.portA.request.put(BRAMRequest{
                    write: False,
                    responseOnWrite: False,
                    address: req.addr,
                    datain: ?});
        
        dir.portA.request.put(BRAMRequest{
                    write: False,
                    responseOnWrite: False,
                    address: req.addr,
                    datain: ?});
        ready <= False;
    endrule

    rule parentRespondsToPart2 if (waitingForRequest && currentlyWorking);
        PackedLine r <- bram.portA.response.get();
        DirData d <- dir.portA.response.get();
        currentlyResponse <= MainMemResp{
            data: r,
            dirdata: d};
        waitingForRequest <= False;
        waitingForIsOk <= True;
    endrule

    rule parentRespondsToPart3 if (waitingForIsOk && currentlyWorking);
        Bool isOk = True;
        MSI y = currentlyCM.msi;
        for (Integer i = 0; i <= 1; i = i + 1) begin
            if (fromInteger(i) != currentlyCM.whichcache) begin
                isOk = isOk && isCompatible(y, currentlyResponse.dirdata.msis[i]); // Possible issue with waiting for request.
            end
        end

        if (isOk) begin
            let d = currentlyResponse.data;
            incomingRequests.deq();
            outgoingMessages.enq(CoherencyMessage{
                addr: response.addr,
                msi: y,
                whichcache: response.whichcache,
                data: d});
            currentlyWorking <= False;
            ready <= True;

            // Write back to memory
            bram.portA.request.put(BRAMRequest{
                        write: unpack(True),
                        responseOnWrite: False,
                        address: currentlyCM.addr,
                        datain: currentlyResponse.data});
        end
        waitingForIsOk <= False;

    endrule


    rule parentReceivesDowngradeResponse if (!waitingForRequest);
        CoherencyMessage r <- incomingResponses.first();
        // I'm gucking fay
        // If I'm getting a downgrade request for something I'm working on, then update my currentlyCm
        if (currentlyWorking && r.LineAddr == currentlyCM.LineAddr) begin
            let newResponse = currentlyResponse;
            if (currentlyResponse.msis[r.whichcache] == M) begin
                newResponse.data = r.data;
            end
            newResponse.dirdata.msis[r.whichcache] = r.msi;
            newResponse.dirdata.waitc[r.whichcache] = False;
            currentlyResponse <= newResponse;
        end
        else begin
            // let slot <- getSlot(r);
            downgradeCM <= r;

            // Else write to bram
            // First get the current data in the bram
            bram.portA.request.put(BRAMRequest{
                        write: unpack(False),
                        responseOnWrite: False,
                        address: req.addr,
                        datain: ?});
            dir.portA.request.put(BRAMRequest{
                        write: unpack(False),
                        responseOnWrite: False,
                        address: req.addr,
                        datain: ?});
            waitingForDowngrade1 <= True;
        end

    endrule

    rule parentRecievesDowngradeResponse2 if (waitingForDowngrade1);
        PackedLine r <- bram.portA.response.get();
        DirData d <- bram.portA.response.get();
        downgradeResponse <= MainMemResp{
            data: r,
            dirdata: d};
        waitingForDowngrade1 <= False;
        waitingForDowngrade2 <= True;
    endrule

    rule parentRecievesDowngradeResponse3 if (waitingForDowngrade2);
        MainMemResp newResponse = downgradeResponse;
        newResponse.dirdata.msis[downgradeCM.whichcache] = downgradeCM.msi;
        newResponse.dirdata.waitc[downgradeCM.whichcache] = False;
        if (downgradeCM.msis[downgradeCM.whichcache] == M) begin
            newResponse.data = downgradeCM.data;
        end
        // Write to bram
        bram.portA.request.put(BRAMRequest{
                    write: unpack(True),
                    responseOnWrite: False,
                    address: downgradeResponse.addr,
                    datain: newResponse.data});
        dir.portA.request.put(BRAMRequest{
                    write: unpack(True),
                    responseOnWrite: False,
                    address: downgradeResponse.addr,
                    datain: newResponse.dirdata});
        waitingForDowngrade2 <= False;
    endrule


    method Action putI(MainMemReq req);
        bram.portA.request.put(BRAMRequest{
                    write: unpack(req.write),
                    responseOnWrite: False,
                    address: req.addr,
                    datain: req.data});
    endmethod

    method ActionValue#(MainMemResp) getI();
        let r <- bram.portA.response.get();
        return r;
    endmethod

    method Action putResponse(CoherencyMessage message);
        incomingResponses.enq(message);
    endmethod

    method Action putRequest(CoherencyMessage message);
        incomingRequests.enq(message);
    endmethod

    method ActionValue#(CoherencyMessage) getRequest();
        let r <- outgoingMessages.first();
        outgoingMessages.deq();
        return r;
    endmethod
endmodule
