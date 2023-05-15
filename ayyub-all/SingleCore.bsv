import RVUtil::*;
import BRAM::*;
import pipelined::*;
import FIFO::*;
import MemTypes::*;
import DCache::*;

function Bit#(1) toWrite(Bit#(4) byte_en);
    return byte_en == 0 ? 0 : 1;
endfunction

function Bit#(64) toByteEn(Bit#(1) write);
    return (write == 1) ? signExtend(1'b1) : 0;
endfunction

module mkSingleCore(
    DCache iCache,
    DCache dCache,
    RVIfc rv_core,
    Empty ifc
);
    // Instantiate the dual ported memory
    // BRAM2PortBE#(Bit#(30), Word, 4) bram <- mkBRAM2ServerBE(cfg);

    Reg#(Mem) ireq <- mkRegU;
    Reg#(Mem) dreq <- mkRegU;
    FIFO#(Mem) mmioreq <- mkFIFO;
    let debug = False;
    Reg#(Bit#(32)) cycle_count <- mkReg(0);


    rule tic;
	    cycle_count <= cycle_count + 1;
    endrule


    // Reads instruction memory requests from the processor, forwards to cache
    rule requestI;
        Mem req <- rv_core.getIReq;
        MemReq req2 = MemReq{ addr: req.addr, data: req.data, op: req.byte_en == 0 ? Ld : St };

        if (debug) $display("Get IReq", fshow(req));
        ireq <= req;

        // CacheReq cReq = CacheReq{ write: toWrite(req.byte_en), addr: req.addr, data: req.data };

        iCache.req(req2);
    endrule

    // Sends instruction memory responses to the processor from the cache
    rule responseI;
        Word cacheData <- iCache.resp();

        let req = ireq;
        if (debug) $display("Get IResp ", fshow(req), fshow(cacheData));
        // req.data = cacheData;
        req.data = cacheData;
        rv_core.getIResp(req);
    endrule

    // Reads data memory requests from the processor
    rule requestD;
        Mem req <- rv_core.getDReq;
        MemReq req2 = MemReq{ addr: req.addr, data: req.data, op: req.byte_en == 0 ? Ld : St };

        if (debug) $display("Get DReq", fshow(req));
        dreq <= req;

        // CacheReq cReq = CacheReq{ write: toWrite(req.byte_en), addr: req.addr, data: req.data };

        dCache.req(req2);
    endrule

    // Sends data memory responses to the processor
    rule responseD;
        Word cacheData <- dCache.resp();

        let req = dreq;
        if (debug) $display("Get DResp ", fshow(req), fshow(cacheData));
        req.data = cacheData;
        // req.data = cacheData;
        rv_core.getDResp(req);
    endrule
  
    // Reads MMIO memory requests from the processor
    rule requestMMIO;
        let req <- rv_core.getMMIOReq;
        if (debug) $display("Get MMIOReq", fshow(req));
        if (req.byte_en == 'hf) begin
            if (req.addr == 'hf000_fff4) begin
                // Write integer to STDERR
                        $fwrite(stderr, "%0d", req.data);
                        $fflush(stderr);
            end
        end
        if (req.addr ==  'hf000_fff0) begin
                // Writing to STDERR
                $fwrite(stderr, "%c", req.data[7:0]);
                $fflush(stderr);
        end else
            if (req.addr == 'hf000_fff8) begin
            // Exiting Simulation
                if (req.data == 0) begin
                        $fdisplay(stderr, "  [0;32mPASS[0m");
                end
                else
                    begin
                        $fdisplay(stderr, "  [0;31mFAIL[0m (%0d)", req.data);
                    end
                $fflush(stderr);
                // $finish;
            end

        mmioreq.enq(req);
    endrule

    rule responseMMIO;
        let req = mmioreq.first();
        mmioreq.deq();
        if (debug) $display("Put MMIOResp", fshow(req));
        rv_core.getMMIOResp(req);
    endrule
    
endmodule
