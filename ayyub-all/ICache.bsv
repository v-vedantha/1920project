import Vector::*;
import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Ehr::*;
import MemTypes::*;

typedef enum { Ready, Assess, StartMiss, SendFillReq, WaitFillResp,  FinishProcessStb } CacheState deriving (Eq, FShow, Bits);
typedef enum { Ld, St } ReqType deriving (Eq, FShow, Bits);

typedef struct {
    CacheTag tag;
    LineIndex lineIndex;
    BlockOffset blockOffset;
} AddrInfo deriving (Eq, FShow, Bits, Bounded);

function AddrInfo extractAddrInfo (CacheAddr addr);

    Integer end_multiple = 1;
    Integer end_block_offset = valueOf(NumBlockBits) - 1 + (end_multiple + 1);
    Integer end_cache_line = valueOf(NumCacheLineBits) - 1 + (end_block_offset + 1);
    Integer end_tag = valueOf(NumTagBits) - 1 + (end_cache_line + 1);

    BlockOffset bo = addr[end_block_offset : 2];
    LineIndex li = addr[end_cache_line : end_block_offset + 1];
    CacheTag ct = addr[end_tag : end_cache_line + 1];
    
    AddrInfo info = AddrInfo { tag: ct, lineIndex: li, blockOffset: bo };
    return info;
endfunction


interface Cache;
    // TODO below
  
    method Action putFromProc(CacheReq e); // Make request
    method ActionValue#(Word) getToProc(); // Gives processor returned value
    // method Action dequeProc(); // Removes value from processor return queue
    method ActionValue#(MainMemReq) getToMem(); // Make request to main memory
    method Action putFromMem(MainMemResp e); // Get from main memory
endinterface

module mkCache(Cache);
  
  Reg#(CacheState) cacheState <- mkReg(Ready);



  BRAM_Configure cfg = defaultValue;
  BRAM1Port#( LineIndex, Maybe#(CacheTag) ) tagArray <- mkBRAM1Server(cfg);

  BRAM_Configure cfg2 = defaultValue;
  BRAM1Port#( LineIndex, Line ) dataArray <- mkBRAM1Server(cfg2);

  BRAM_Configure cfg3 = defaultValue;
  BRAM1Port#( LineIndex, Bool ) cleanArray <- mkBRAM1Server(cfg3);

  FIFO#(Word) hitQ <- mkBypassFIFO;

  FIFO#(MainMemReq) memReqQ <- mkFIFO;
  FIFO#(MainMemResp) memRespQ <- mkFIFO;



  Reg#(CacheReq) cacheReq <- mkRegU;
  Reg#(AddrInfo) requestInfo <- mkRegU;

  Reg#(Maybe#(CacheTag)) cacheTableTag <- mkRegU;
  Reg#(Line) cacheTableLine <- mkRegU;
  Reg#(Word) cacheTableData <- mkRegU;
  Reg#(Bool) cacheTableClean <- mkRegU;


  ReqType reqType = cacheReq.write == 1 ? St : Ld;


  Reg#(Bit#(1000)) cycle <- mkReg(0);
  rule cycle_count;
      // $display(cacheState); // { Ready, Assess, StartMiss, SendFillReq, WaitFillResp,  FinishProcessStb }
      cycle <= cycle + 1;
  endrule

  rule assess_rule if (cacheState == Assess);
      // $display("The rule is firing");
  
      Maybe#(CacheTag) maybeTableTag <- tagArray.portA.response.get();

      CacheTag tableTag = fromMaybe(?, maybeTableTag);
      Line tableLine <- dataArray.portA.response.get();
      Word tableData = tableLine[requestInfo.blockOffset];
      Bool tableClean <- cleanArray.portA.response.get();

      Bool isHit = True;

      if (!isValid(maybeTableTag)) isHit = False;
      else if (tableTag != requestInfo.tag) isHit = False;

      if (isHit) begin

        if (reqType == Ld) begin
          hitQ.enq(tableData);
        end
        else begin
          
          Line newLine = take(tableLine);
          newLine[requestInfo.blockOffset] = cacheReq.data;
        
          dataArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                  responseOnWrite: False,
                                                  address: requestInfo.lineIndex,
                                                  datain: newLine});

          cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                  responseOnWrite: False,
                                                  address: requestInfo.lineIndex,
                                                  datain: False});
          hitQ.enq(0);
        end

        cacheState <= Ready;
      end
      else begin
        cacheTableTag <= maybeTableTag;
        cacheTableLine <= tableLine;
        cacheTableData <= tableData;
        cacheTableClean <= tableClean;

        cacheState <= StartMiss;
      end

  endrule

  rule start_miss_rule if (cacheState == StartMiss);
     
      // Writeback request
      if (isValid(cacheTableTag) && !cacheTableClean) begin
        CacheTag tableTag = fromMaybe(?, cacheTableTag);
        LineAddr la = {tableTag, requestInfo.lineIndex};
        MainMemReq writeback_req = MainMemReq { write: 1'b1, addr: la, data: cacheTableLine };
        memReqQ.enq(writeback_req);

        cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                  responseOnWrite: False,
                                                  address: requestInfo.lineIndex,
                                                  datain: True});
      end

      cacheState <= SendFillReq;
  endrule

  rule send_fill_rule if (cacheState == SendFillReq);
      LineAddr la = { requestInfo.tag, requestInfo.lineIndex };
  
      MainMemReq missing_line_req = MainMemReq { write: 1'b0, addr: la, data: ? };
      memReqQ.enq(missing_line_req);

      cacheState <= WaitFillResp;
  endrule

  rule wait_fill_rule if (cacheState == WaitFillResp);
      // $display("Entered rule");
  
      MainMemResp resp = memRespQ.first();

      tagArray.portA.request.put(BRAMRequest{write: True, // False for read
                                            responseOnWrite: False,
                                            address: requestInfo.lineIndex,
                                            datain: Valid(requestInfo.tag)});
      
      if (reqType == Ld) begin
        dataArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                  responseOnWrite: False,
                                                  address: requestInfo.lineIndex,
                                                  datain: resp});

        cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                responseOnWrite: False,
                                                address: requestInfo.lineIndex,
                                                datain: True});

        Word respData = resp[requestInfo.blockOffset];
        hitQ.enq(respData);
      end
      else begin
        
        Line newLine = take(resp);
        newLine[requestInfo.blockOffset] = cacheReq.data;
      
        dataArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                responseOnWrite: False,
                                                address: requestInfo.lineIndex,
                                                datain: newLine});

        cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                responseOnWrite: False,
                                                address: requestInfo.lineIndex,
                                                datain: False});
        hitQ.enq(0);
      end

      memRespQ.deq();

      cacheState <= Ready;
  endrule

  method Action putFromProc(CacheReq e) if (cacheState == Ready);
      AddrInfo ai = extractAddrInfo(e.addr);
      
      tagArray.portA.request.put(BRAMRequest{write: False, // False for read
                                            responseOnWrite: False,
                                            address: ai.lineIndex,
                                            datain: ?});
      
      dataArray.portA.request.put(BRAMRequest{write: False, // False for read
                                            responseOnWrite: False,
                                            address: ai.lineIndex,
                                            datain: ?});
      
      cleanArray.portA.request.put(BRAMRequest{write: False, // False for read
                                            responseOnWrite: False,
                                            address: ai.lineIndex,
                                            datain: ?});
      
      cacheReq <= e;
      requestInfo <= ai;

      cacheState <= Assess;
  endmethod

  method ActionValue#(Word) getToProc();
    hitQ.deq();  
    return hitQ.first();
  endmethod

  method ActionValue#(MainMemReq) getToMem();
      memReqQ.deq();
      return memReqQ.first();
  endmethod

  method Action putFromMem(MainMemResp e);
      memRespQ.enq(e);
  endmethod


endmodule
