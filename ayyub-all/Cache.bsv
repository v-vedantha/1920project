import Vector::*;
import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Ehr::*;
import MemTypes::*;

Integer addrSize = 32;

Integer numCacheLines = 128;
Integer numWordsPerLine = 16;

Integer numBlockBits = 4; // log2(16);
Integer numCacheLineBits = 7; // log2(128)
Integer numTagBits = 21; // 32 - 7 - 4;

typedef Bit#(4) BlockOffset;
typedef Bit#(7) LineIndex;
typedef Bit#(21) CacheTag;

typedef enum { Ready, Assess, StartMiss, SendFillReq, WaitFillResp,  FinishProcessStb } CacheState deriving (Eq, FShow, Bits);
typedef enum { Ld, St } ReqType deriving (Eq, FShow, Bits);

typedef struct {
    CacheTag tag;
    LineIndex lineIndex;
    BlockOffset blockOffset;
} AddrInfo deriving (Eq, FShow, Bits, Bounded);

function AddrInfo extractAddrInfo (LineAddr addr);
    
    BlockOffset bo = addr[numBlockBits - 1 : 0];
    LineIndex li = addr[numBlockBits + numCacheLineBits - 1 : numBlockBits];
    CacheTag ct = addr[addrSize - 1 : numBlockBits + numCacheLineBits];
    
    AddrInfo info = AddrInfo { tag: ct, lineIndex: li, blockOffset: bo };
    return info;
endfunction





interface Cache;
    method Action putFromProc(MainMemReq e); // Make request
    method ActionValue#(MainMemResp) getToProc(); // Get request
    method ActionValue#(MainMemReq) getToMem(); // Make request to main memory
    method Action putFromMem(MainMemResp e); // Get from main memory
endinterface

module mkCache(Cache);
  
  Reg#(CacheState) cacheState <- mkReg(Ready);



  BRAM_Configure cfg = defaultValue;
  BRAM1Port#( Bit#(7), Maybe#(CacheTag) ) tagArray <- mkBRAM1Server(cfg);

  BRAM_Configure cfg2 = defaultValue;
  BRAM1Port#( Bit#(7), Vector#(16, Word) ) dataArray <- mkBRAM1Server(cfg2);

  BRAM_Configure cfg3 = defaultValue;
  BRAM1Port#( Bit#(7), Bool ) cleanArray <- mkBRAM1Server(cfg3);

  FIFO#(MainMemResp) hitQ <- mkBypassFIFO;
  // Reg#(MainMemReq) missReq <- mkRegU;

  FIFO#(MainMemReq) memReqQ <- mkFIFO;
  FIFO#(MainMemResp) memRespQ <- mkFIFO;



  Reg#(MainMemReq) cacheReq <- mkRegU;
  Reg#(AddrInfo) requestInfo <- mkRegU;

  Reg#(Maybe#(CacheTag)) cacheTableTag <- mkRegU;
  Reg#(CacheLine) cacheTableLine <- mkRegU;
  Reg#(Bool) cacheTableClean <- mkRegU;

  FIFOF#(MainMemReq) stb <- mkSizedFIFOF(1);

  Ehr#(2, Bool) lockCache <- mkEhr(False);


  ReqType reqType = cacheReq.write == 1 ? St : Ld;


  // Reg#(Bit#(1000)) cycle <- mkReg(0);
  // rule cycle_count;
  //     $display(cacheState); // { Ready, Assess, StartMiss, SendFillReq, WaitFillResp,  FinishProcessStb }
  //     cycle <= cycle + 1;
  // endrule

  rule assess_rule if (cacheState == Assess);
      // $display("The rule is firing");
  
      Maybe#(CacheTag) maybeTableTag <- tagArray.portA.response.get();

      CacheTag tableTag = fromMaybe(?, maybeTableTag);
      CacheLine tableLine <- dataArray.portA.response.get();
      Bool tableClean <- cleanArray.portA.response.get();

      Bool gotFromStb = False;
      if (reqType == Ld && stb.notEmpty()) begin
        MainMemReq buf_req = stb.first();

        // Check if store buffer val matches
        if (buf_req.addr == cacheReq.addr) begin
          hitQ.enq(buf_req.data);
          gotFromStb = True;

          cacheState <= Ready;
        end
      end

      if (!gotFromStb) begin
        Bool isHit = True;

        if (reqType == St && !isValid(maybeTableTag)) isHit = True;
        else if (!isValid(maybeTableTag)) isHit = False;
        else if (tableTag != requestInfo.tag) isHit = False;

        if (isHit) begin

          if (reqType == Ld) begin
            hitQ.enq(tableData);
          end
          else begin
            dataArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                    responseOnWrite: False,
                                                    address: requestInfo.lineIndex,
                                                    datain: cacheReq.data});

            cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                    responseOnWrite: False,
                                                    address: requestInfo.lineIndex,
                                                    datain: False});
          end

          cacheState <= Ready;
        end
        else begin
          cacheTableTag <= maybeTableTag;
          cacheTableLine <= tableLine;
          cacheTableClean <= tableClean;

          cacheState <= StartMiss;
        end
      end

  endrule

  rule start_miss_rule if (cacheState == StartMiss);
     
      // Writeback request
      if (isValid(cacheTableTag) && !cacheTableClean) begin
        CacheTag tableTag = fromMaybe(?, cacheTableTag);
        MainMemReq writeback_req = MainMemReq { write: 1'b1, addr: {tableTag, requestInfo.lineIndex}, data: cacheTableData };
        memReqQ.enq(writeback_req);

        cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                  responseOnWrite: False,
                                                  address: requestInfo.lineIndex,
                                                  datain: True});
      end

      cacheState <= SendFillReq;
  endrule

  rule send_fill_rule if (cacheState == SendFillReq);
      MainMemReq missing_line_req = MainMemReq { write: 1'b0, addr: cacheReq.addr, data: ? };
      memReqQ.enq(missing_line_req);

      cacheState <= WaitFillResp;
  endrule

  rule wait_fill_rule if (cacheState == WaitFillResp);
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

        hitQ.enq(resp);
      end
      else begin
        dataArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                  responseOnWrite: False,
                                                  address: requestInfo.lineIndex,
                                                  datain: cacheReq.data});

        cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                responseOnWrite: False,
                                                address: requestInfo.lineIndex,
                                                datain: False});
      end

      memRespQ.deq();

      cacheState <= Ready;
  endrule

  rule start_process_stb if (cacheState == Ready && !lockCache[1]);
      MainMemReq buf_req = stb.first();
      AddrInfo ai = extractAddrInfo(buf_req.addr);

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
      
      cacheReq <= buf_req;
      requestInfo <= ai;

      stb.deq();

      cacheState <= Assess;
  endrule

  rule clear_lock;
      lockCache[1] <= False;
  endrule

  method Action putFromProc(MainMemReq e) if (cacheState == Ready);
      if (e.write == 1) stb.enq(e);
      else lockCache[0] <= True;
  
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

  method ActionValue#(MainMemResp) getToProc();
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
