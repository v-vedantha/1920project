import RVUtil::*;
import BRAM::*;
import pipelined::*;
import FIFO::*;
import MemTypes::*;
import ICache::*;

function Bit#(1) toWrite(Bit#(4) byte_en);
    return byte_en == 0 ? 0 : 1;
endfunction

function Bit#(64) toByteEn(Bit#(1) write);
    return (write == 1) ? signExtend(1'b1) : 0;
endfunction

module mktop_pipelined(Empty);
    // Instantiate the dual ported memory
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "memlines.vmh";
    BRAM2Port#(LineAddr, PackedLine) mainMem <- mkBRAM2Server(cfg);
    // BRAM2PortBE#(Bit#(30), Word, 4) bram <- mkBRAM2ServerBE(cfg);

    RVIfc rv_core <- mkpipelined;
    Reg#(Mem) ireq <- mkRegU;
    Reg#(Mem) dreq <- mkRegU;
    FIFO#(Mem) mmioreq <- mkFIFO;
    let debug = False;
    Reg#(Bit#(32)) cycle_count <- mkReg(0);

    Cache iCache <- mkCache();
    Cache dCache <- mkCache();

    rule tic;
	    cycle_count <= cycle_count + 1;
    endrule


    rule iCacheToMain;
        MainMemReq lineReq <- iCache.getToMem();

        mainMem.portB.request.put(BRAMRequest{
            write: lineReq.write == 1,
            responseOnWrite: False,
            address: lineReq.addr,
            datain: pack(lineReq.data)});

        // mainMem.put(lineReq);
    endrule
    rule mainToICache;
        let resp <- mainMem.portB.response.get();
        MainMemResp line = unpack(resp);
        iCache.putFromMem(line);
    endrule

    rule dCacheToMain;
        MainMemReq lineReq <- dCache.getToMem();

        mainMem.portA.request.put(BRAMRequest{
            write: lineReq.write == 1,
            responseOnWrite: False,
            address: lineReq.addr,
            datain: pack(lineReq.data)});

        // mainMem.put(lineReq);
    endrule
    rule mainToDCache;
        let resp <- mainMem.portA.response.get();
        MainMemResp line = unpack(resp);
        dCache.putFromMem(line);
    endrule



    // Reads instruction memory requests from the processor, forwards to cache
    rule requestI;
        Mem req <- rv_core.getIReq;

        if (debug) $display("Get IReq", fshow(req));
        ireq <= req;

        CacheReq cReq = CacheReq{ write: toWrite(req.byte_en), addr: req.addr, data: req.data };

        iCache.putFromProc(cReq);
    endrule

    // Sends instruction memory responses to the processor from the cache
    rule responseI;
        Word cacheData <- iCache.getToProc();

        let req = ireq;
        if (debug) $display("Get IResp ", fshow(req), fshow(cacheData));
        req.data = cacheData;
        rv_core.getIResp(req);
    endrule

    // Reads data memory requests from the processor
    rule requestD;
        Mem req <- rv_core.getDReq;

        if (debug) $display("Get DReq", fshow(req));
        dreq <= req;

        CacheReq cReq = CacheReq{ write: toWrite(req.byte_en), addr: req.addr, data: req.data };

        dCache.putFromProc(cReq);
    endrule

    // Sends data memory responses to the processor
    rule responseD;
        Word cacheData <- dCache.getToProc();

        let req = dreq;
        if (debug) $display("Get DResp ", fshow(req), fshow(cacheData));
        req.data = cacheData;
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
                $finish;
            end

        mmioreq.enq(req);
    endrule

    // Reads MMIO memory requests from the processor
    rule responseMMIO;
        let req = mmioreq.first();
        mmioreq.deq();
        if (debug) $display("Put MMIOResp", fshow(req));
        rv_core.getMMIOResp(req);
    endrule
    
endmodule
