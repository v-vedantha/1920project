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

typedef 32 InstSz;
typedef Bit#(InstSz) Instruction;
interface RefIMem;
	method Action fetch(CacheAddr pc, Instruction inst);
endinterface

interface RefDMem;
	method Action issue(MemReq req);
	method Action commit(MemReq req, Maybe#(Line) line, Maybe#(MemResp) resp);
	// line is the original cache line (before write is done)
	// set it to invalid if you don't want to check the value 
	// or you don't know the value (e.g. when you bypass from stq or when store-cond fail)
endinterface
typedef enum { Ready, Assess, StartMiss, SendFillReq, WaitFillResp, FinalResp } CacheState deriving (Eq, FShow, Bits);
typedef enum { DowngradeStart, DowngradeFinish } DowngradeState deriving (Eq, FShow, Bits);
// typedef enum { Ld, St } ReqType deriving (Eq, FShow, Bits);


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



  Reg#(MemReq) cacheReq <- mkRegU;
  Reg#(AddrInfo) requestInfo <- mkRegU;

  Reg#(Maybe#(CacheTag)) cacheTableTag <- mkRegU;
  Reg#(Line) cacheTableLine <- mkRegU;
  Reg#(Word) cacheTableData <- mkRegU;
  // Reg#(Bool) cacheTableClean <- mkRegU;
  Reg#(MSI) cacheTableMSI <- mkRegU;

  Reg#(Word) finalRespData <- mkRegU;

  Bool responseOnWrite = False;

  Bool debug = True;


  // ReqType reqType = cacheReq.write == 1 ? St : Ld;
  MemOp reqType = cacheReq.op;


  Reg#(Bit#(1000)) cycle <- mkReg(0);
  rule cycle_count;
      $display("%x %x", cacheState, downgradeState); // { Ready, Assess, StartMiss, SendFillReq, WaitFillResp, FinalResp } | { DowngradeStart, DowngradeFinish }
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

      $display("What the fuck is my state in assess: %x", tableMSI);
      
      // Bool isHit = True;

      // if (!isValid(maybeTableTag)) isHit = False;
      // else if (tableTag != requestInfo.tag) isHit = False;

      Bool isHit = !(!isValid(maybeTableTag) || tableTag != requestInfo.tag);

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

            if (debug) begin
              $display("Assess rule just wrote to data");
              $display(fshow(newLine));
            end

            // cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
            //                                         responseOnWrite: False,
            //                                         address: requestInfo.lineIndex,
            //                                         datain: False});
            if (responseOnWrite) hitQ.enq(0); // Dummy resp for responseOnWrite

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

        CacheMemResp writeback_resp = CacheMemResp{ child: id, addr: la, state: I, data: tagged Valid(cacheTableLine) };
        // $display("Response type 1");
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
      CacheMemReq missing_line_req = CacheMemReq{ child: id, addr: la, state: new_state };
      toMem.enq_req(missing_line_req);
      // $display("Requesting address ", fshow(missing_line_req));

      cacheState <= WaitFillResp;
  endrule

  rule wait_fill_rule if (cacheState == WaitFillResp && fromMem.hasResp);
      // $display("Entered rule");
  
      // MainMemResp resp = memRespQ.first();

      CacheMemResp resp = fromMem.first().Resp;
      // $display("Response is ", fshow(resp));
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
        
        if (debug) begin
          $display("Wait fill rule on load just wrote to data");
          $display(fshow(resp_line));
        end

        // cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
        //                                         responseOnWrite: False,
        //                                         address: requestInfo.lineIndex,
        //                                         datain: True});

        Word respData = resp_line[requestInfo.blockOffset];
        finalRespData <= respData;
        // hitQ.enq(respData);
      end
      else begin
        Line newLine = isValid(resp.data) ? take(resp_line) : take(cacheTableLine); // Assuming that it is only Invalid for store hits when in S
        newLine[requestInfo.blockOffset] = cacheReq.data;
      
        dataArray.portA.request.put(BRAMRequest{write: True, // False for read
                                                responseOnWrite: False,
                                                address: requestInfo.lineIndex,
                                                datain: newLine});
        
        if (debug) begin
          $display("Wait fill rule on store just wrote to data");
          $display(fshow(resp_line));
          $display(fshow(cacheReq.data));
          $display(requestInfo.blockOffset);
          $display(fshow(newLine));
        end

        // cleanArray.portA.request.put(BRAMRequest{write: True, // False for read
        //                                         responseOnWrite: False,
        //                                         address: requestInfo.lineIndex,
        //                                         datain: False});
        // hitQ.enq(0); // Dummy resp for responseOnWrite
      end

      // memRespQ.deq();
      
      fromMem.deq();

      cacheState <= FinalResp;
  endrule

  rule final_resp_rule if (cacheState == FinalResp);
    if (reqType == Ld || responseOnWrite) hitQ.enq(reqType == Ld ? finalRespData : 0);
    cacheState <= Ready;
  endrule

  rule downgrade_start_rule if (cacheState != FinalResp &&
                                downgradeState == DowngradeStart &&
                                fromMem.hasReq && !fromMem.hasResp);

    CacheMemReq req = fromMem.first().Req;
    fromMem.deq();
    
    LineIndex li = req.addr[valueOf(NumCacheLineBits) - 1 : 0];
    // AddrInfo ai = extractAddrInfo(req.addr);
    MSI currentState = cacheMSIs[li];
    $display("Downgrade start rule from MSI ", fshow(currentState));
    
    if (currentState > req.state) begin
      if (currentState == M) begin
        dataArray.portB.request.put(BRAMRequest{write: False, // False for read
                                              responseOnWrite: False,
                                              address: li,
                                              datain: ?});
        downgradeState <= DowngradeFinish;
      end else begin
        cacheMSIs[li] <= req.state;
        // $display("Response type 2");
        toMem.enq_resp(CacheMemResp{ child: id, addr: req.addr, state: req.state, data: Invalid});
      end
    end

    downgradeReq <= req;
  endrule

  rule downgrade_end_rule if (cacheState != FinalResp &&
                              downgradeState == DowngradeFinish);
    Line data <- dataArray.portB.response.get();
    // AddrInfo ai = extractAddrInfo(downgradeReq.addr);
    LineIndex li = downgradeReq.addr[valueOf(NumCacheLineBits) - 1 : 0];
    cacheMSIs[li] <= downgradeReq.state;

    // $display("Response type 3");
    CacheMemResp resp = CacheMemResp{ child: id, addr: downgradeReq.addr, state: downgradeReq.state, data: tagged Valid(data) };
    toMem.enq_resp(resp);

    $display("Returning data", fshow(resp));
    downgradeState <= DowngradeStart;
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
      
      // cleanArray.portA.request.put(BRAMRequest{write: False, // False for read
      //                                       responseOnWrite: False,
      //                                       address: ai.lineIndex,
      //                                       datain: ?});
      
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
