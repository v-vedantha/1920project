import Vector::*;
import BRAM::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Ehr::*;
import MemTypes::*;
import MessageRouter::*;
import MessageFifo::*;
import CoherencyTypes::*;

typedef enum { Ready, Assess, StartMiss, SendFillReq, WaitFillResp, FinalResp} CacheState deriving (Eq, FShow, Bits);
typedef enum { DowngradeStart, DowngradeFinish} DowngradeState deriving (Eq, FShow, Bits);
// typedef enum { Ld, St } ReqType deriving (Eq, FShow, Bits);

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


// interface Cache;
//     // TODO below
  
//     method Action putFromProc(CacheReq e); // Make request
//     method ActionValue#(Word) getToProc(); // Gives processor returned value
//     // method Action dequeProc(); // Removes value from processor return queue
//     method ActionValue#(MainMemReq) getToMem(); // Make request to main memory
//     method Action putFromMem(MainMemResp e); // Get from main memory
// endinterface


interface DCache;
  method Action req(MemReq r);
  method ActionValue#(MemResp) resp;
endinterface


module mkDCache#(CoreID id)(MessageGet fromMem, MessagePut toMem, RefDMem refDMem, DCache ifc);
  
  Reg#(CacheState) cacheState <- mkReg(Ready);

  Reg#(DowngradeState) downgradeState <- mkReg(DowngradeStart);
  Reg#(CacheMemReq) downgradeReq <- mkRegU;



  BRAM_Configure cfg = defaultValue;
  BRAM1Port#( LineIndex, Maybe#(CacheTag) ) tagArray <- mkBRAM1Server(cfg);

  BRAM_Configure cfg2 = defaultValue;
  BRAM2Port#( LineIndex, Line ) dataArray <- mkBRAM2Server(cfg2);

  // BRAM_Configure cfg3 = defaultValue;
  // BRAM1Port#( LineIndex, Bool ) cleanArray <- mkBRAM1Server(cfg3);

  Vector#(NumCacheLines, Reg#(MSI)) cacheMSIs <- replicateM( mkReg(I) ); 

  FIFO#(Word) hitQ <- mkBypassFIFO;

  FIFO#(MainMemReq) memReqQ <- mkFIFO;
  FIFO#(MainMemResp) memRespQ <- mkFIFO;



  Reg#(CacheReq) cacheReq <- mkRegU;
  Reg#(AddrInfo) requestInfo <- mkRegU;

  Reg#(Maybe#(CacheTag)) cacheTableTag <- mkRegU;
  Reg#(Line) cacheTableLine <- mkRegU;
  Reg#(Word) cacheTableData <- mkRegU;
  // Reg#(Bool) cacheTableClean <- mkRegU;
  Reg#(MSI) cacheTableMSI <- mkRegU;

  Reg#(Word) finalRespData <- mkRegU;


  // ReqType reqType = cacheReq.write == 1 ? St : Ld;
  MemOp reqType = cacheReq.write == 1 ? St : Ld;


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
      // Bool tableClean <- cleanArray.portA.response.get();
      MSI tableMSI = cacheMSIs[requestInfo.lineIndex];

      Word tableData = tableLine[requestInfo.blockOffset];

      
      Bool isHit = True;

      if (!isValid(maybeTableTag)) isHit = False;
      else if (tableTag != requestInfo.tag) isHit = False;

      if (isHit) begin

        if (reqType == Ld) begin
          hitQ.enq(tableData);

          cacheState <= Ready;
        end
        else begin

          if (tableMSI == M) begin

            Line newLine = take(tableLine);
            newLine[requestInfo.blockOffset] = cacheReq.data;
            
            dataArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                    responseOnWrite: False,
                                                    address: requestInfo.lineIndex,
                                                    datain: newLine});

            // cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
            //                                         responseOnWrite: False,
            //                                         address: requestInfo.lineIndex,
            //                                         datain: False});
            hitQ.enq(0); // Dummy resp for responseOnWrite

            cacheState <= Ready;
          end
          else begin
            cacheState <= SendFillReq;
          end
        end
      end
      else begin
        cacheState <= StartMiss;
      end

      cacheTableTag <= maybeTableTag;
      cacheTableLine <= tableLine;
      // cacheTableClean <= tableClean;
      cacheTableMSI <= tableMSI;
      cacheTableData <= tableData;
      
  endrule

  rule start_miss_rule if (cacheState == StartMiss);
     
      // Writeback request
      // if (isValid(cacheTableTag) && !cacheTableClean) begin
      //   CacheTag tableTag = fromMaybe(?, cacheTableTag);
      //   LineAddr la = {tableTag, requestInfo.lineIndex};
      //   MainMemReq writeback_req = MainMemReq { write: 1'b1, addr: la, data: cacheTableLine };
      //   memReqQ.enq(writeback_req);

      //   cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
      //                                             responseOnWrite: False,
      //                                             address: requestInfo.lineIndex,
      //                                             datain: True});
      // end


      if (cacheTableMSI != I) begin
        CacheTag tableTag = fromMaybe(?, cacheTableTag);
        LineAddr la = {tableTag, requestInfo.lineIndex};

        CacheMemResp writeback_resp = CacheMemResp{ child: id, addr: zeroExtend(la), state: I, data: tagged Valid(cacheTableLine) };
        toMem.enq_resp(writeback_resp);

        // MainMemReq writeback_req = MainMemReq { write: 1'b1, addr: la, data: cacheTableLine };
        // memReqQ.enq(writeback_req);

        // cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
        //                                           responseOnWrite: False,
        //                                           address: requestInfo.lineIndex,
        //                                           datain: True});
      end

      cacheState <= SendFillReq;
  endrule

  rule send_fill_rule if (cacheState == SendFillReq);
      LineAddr la = { requestInfo.tag, requestInfo.lineIndex };
  
      // MainMemReq missing_line_req = MainMemReq { write: 1'b0, addr: la, data: ? };
      // memReqQ.enq(missing_line_req);

      // typedef struct{
      //     CoreID      child;
      //     CacheAddr        addr;
      //     MSI         state;
      // } CacheMemReq

      MSI new_state = (reqType == Ld) ? S : M;
      CacheMemReq missing_line_req = CacheMemReq{ child: id, addr: zeroExtend(la), state: new_state };
      toMem.enq_req(missing_line_req);

      cacheState <= WaitFillResp;
  endrule

  rule wait_fill_rule if (cacheState == WaitFillResp && fromMem.hasResp);
      // $display("Entered rule");
  
      // MainMemResp resp = memRespQ.first();

      CacheMemResp resp = fromMem.first().Resp;
      Line resp_line = fromMaybe(?, resp.data);

      tagArray.portA.request.put(BRAMRequest{write: True, // False for read
                                            responseOnWrite: False,
                                            address: requestInfo.lineIndex,
                                            datain: Valid(requestInfo.tag)});

      cacheMSIs[requestInfo.lineIndex] <= resp.state;
      
      if (reqType == Ld) begin
        dataArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                  responseOnWrite: False,
                                                  address: requestInfo.lineIndex,
                                                  datain: resp_line});

        // cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
        //                                         responseOnWrite: False,
        //                                         address: requestInfo.lineIndex,
        //                                         datain: True});

        Word respData = resp_line[requestInfo.blockOffset];
        finalRespData <= respData
        // hitQ.enq(respData);
      end
      else begin
        
        Line newLine = take(resp_line);
        newLine[requestInfo.blockOffset] = cacheReq.data;
      
        dataArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                responseOnWrite: False,
                                                address: requestInfo.lineIndex,
                                                datain: newLine});

        // cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
        //                                         responseOnWrite: False,
        //                                         address: requestInfo.lineIndex,
        //                                         datain: False});
        // hitQ.enq(0); // Dummy resp for responseOnWrite
      end

      // memRespQ.deq();
      
      fromMem.deq();

      finalRespLine <= resp_line;
      cacheState <= FinalResp;
  endrule

  rule final_resp_rule if (cacheState == FinalResp);
    hitQ.enq(reqType == Ld ? final_resp_rule : 0);
    cacheState <= Ready;
  endrule

  rule downgrade_start_rule if (cacheState != FinalResp &&
                                downgradeState == DowngradeStart &&
                                fromMem.hasReq && !fromMem.hasResp);

    CacheMemReq req = fromMem.first().Req;
    fromMem.deq();
    
    AddrInfo ai = extractAddrInfo(req.addr);
    MSI currentState = cacheMSIs[ai.lineIndex];
    
    if (currentState > req.msi) begin
      if (currentState == M) begin
        dataArray.portB.request.put(BRAMRequest{write: False, // False for read
                                              responseOnWrite: False,
                                              address: ai.lineIndex,
                                              datain: ?});
        downgradeState <= DowngradeFinish;
      end else begin
        toMem.enq_resp(CacheMemResp{ child: id, addr: req.addr, state: req.msi, data: Invalid});
      end
    end

    downgradeReq <= req;
  endrule

  rule downgrade_end_rule if (cacheState != FinalResp &&
                              downgradeState == DowngradeFinish);
    Line data = dataArray.portB.response.get();
    AddrInfo ai = extractAddrInfo(downgradeReq.addr);
    cacheMSIs[ai.lineIndex] <= downgradeReq.msi;

    toMem.enq_resp(CacheMemResp{ child: id, addr: req.addr, state: downgradeReq.msi, data: tagged Valid(data) });
  endrule

  method Action req(MemReq r);

      AddrInfo ai = extractAddrInfo(r.addr);
      
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
      
      cacheReq <= r;
      requestInfo <= ai;

      cacheState <= Assess;

  endmethod
  
  method ActionValue#(MemResp) resp;
    hitQ.deq();  
    return hitQ.first();
  endmethod

  // method Action putFromProc(CacheReq e) if (cacheState == Ready);
  //     AddrInfo ai = extractAddrInfo(e.addr);
      
  //     tagArray.portA.request.put(BRAMRequest{write: False, // False for read
  //                                           responseOnWrite: False,
  //                                           address: ai.lineIndex,
  //                                           datain: ?});
      
  //     dataArray.portA.request.put(BRAMRequest{write: False, // False for read
  //                                           responseOnWrite: False,
  //                                           address: ai.lineIndex,
  //                                           datain: ?});
      
  //     cleanArray.portA.request.put(BRAMRequest{write: False, // False for read
  //                                           responseOnWrite: False,
  //                                           address: ai.lineIndex,
  //                                           datain: ?});
      
  //     cacheReq <= e;
  //     requestInfo <= ai;

  //     cacheState <= Assess;
  // endmethod

  // method ActionValue#(Word) getToProc();
  //   hitQ.deq();  
  //   return hitQ.first();
  // endmethod

  // method ActionValue#(MainMemReq) getToMem();
  //     memReqQ.deq();
  //     return memReqQ.first();
  // endmethod

  // method Action putFromMem(MainMemResp e);
  //     memRespQ.enq(e);
  // endmethod


endmodule
