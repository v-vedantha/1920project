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

typedef enum { Ready, Assess, StartMiss, SendFillReq, WaitFillResp, FinalResp } CacheState deriving (Eq, FShow, Bits);
typedef enum { DowngradeStart, DowngradeFinish } DowngradeState deriving (Eq, FShow, Bits);

interface DCache;
  method Action req(MemReq r);
  method ActionValue#(MemResp) resp;
endinterface


module mkDCache#(CoreID id)(MessageGet fromMem, MessagePut toMem, RefDMem refDMem, DCache ifc);
  
  Reg#(CacheState) cacheState <- mkReg(Ready);
  Reg#(DowngradeState) downgradeState <- mkReg(DowngradeStart);


  BRAM_Configure cfg = defaultValue;
  BRAM1Port#( LineIndex, Maybe#(CacheTag) ) tagArray <- mkBRAM1Server(cfg);

  BRAM_Configure cfg2 = defaultValue;
  BRAM2Port#( LineIndex, Line ) dataArray <- mkBRAM2Server(cfg2);

  Vector#(NumCacheLines, Reg#(MSI)) cacheMSIs <- replicateM( mkReg(I) ); 


  FIFO#(Word) hitQ <- mkBypassFIFO;
  FIFO#(MainMemReq) memReqQ <- mkFIFO;
  FIFO#(MainMemResp) memRespQ <- mkFIFO;


  Reg#(MemReq) cacheReq <- mkRegU;
  Reg#(AddrInfo) requestInfo <- mkRegU;

  Reg#(Maybe#(CacheTag)) cacheTableTag <- mkRegU;
  Reg#(Line) cacheTableLine <- mkRegU;
  Reg#(Word) cacheTableData <- mkRegU;
  Reg#(MSI) cacheTableMSI <- mkRegU;

  Reg#(Word) finalRespData <- mkRegU;
  
  Reg#(CacheMemReq) downgradeReq <- mkRegU;


  Bool responseOnWrite = True;
  Bool debug = False;


  MemOp reqType = cacheReq.op;


  Reg#(Bit#(1000)) cycle <- mkReg(0);
  rule cycle_count;
      // $display("%x %x", cacheState, downgradeState); // { Ready, Assess, StartMiss, SendFillReq, WaitFillResp, FinalResp } | { DowngradeStart, DowngradeFinish }
      cycle <= cycle + 1;
  endrule

  rule assess_rule if (cacheState == Assess);
  
      Maybe#(CacheTag) maybeTableTag <- tagArray.portA.response.get();

      CacheTag tableTag = fromMaybe(?, maybeTableTag);
      Line tableLine <- dataArray.portA.response.get();
      MSI tableMSI = cacheMSIs[requestInfo.lineIndex];

      Word tableData = tableLine[requestInfo.blockOffset];

      Bool isHit = isValid(maybeTableTag) && (tableTag == requestInfo.tag);

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
      cacheTableMSI <= tableMSI;
      cacheTableData <= tableData;
      
  endrule

  rule start_miss_rule if (cacheState == StartMiss);
      
      if (cacheTableMSI != I) begin
        CacheTag tableTag = fromMaybe(?, cacheTableTag);
        LineAddr la = {tableTag, requestInfo.lineIndex};

        CacheMemResp writeback_resp = CacheMemResp{ child: id, addr: la, state: I, data: cacheTableMSI == M ? tagged Valid(cacheTableLine) : Invalid };
        toMem.enq_resp(writeback_resp);

        cacheMSIs[requestInfo.lineIndex] <= I;
        cacheTableMSI <= I;
      end

      cacheState <= SendFillReq;
  endrule

  rule send_fill_rule if (cacheState == SendFillReq);
      LineAddr la = { requestInfo.tag, requestInfo.lineIndex };

      MSI new_state = (reqType == Ld) ? S : M;
      CacheMemReq missing_line_req = CacheMemReq{ child: id, addr: la, state: new_state };
      toMem.enq_req(missing_line_req);

      if (debug) begin
        $display("Requesting address ", fshow(missing_line_req));
      end

      cacheState <= WaitFillResp;
  endrule

  rule wait_fill_rule if (cacheState == WaitFillResp && fromMem.hasResp);

      CacheMemResp resp = fromMem.first().Resp;

      if (debug) begin
        $display("Response is ", fshow(resp));
      end

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

        Word respData = resp_line[requestInfo.blockOffset];
        finalRespData <= respData;
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

      end
      
      fromMem.deq();

      cacheState <= FinalResp;
  endrule

  rule final_resp_rule if (cacheState == FinalResp);
    if (reqType == Ld || responseOnWrite) begin
      if (debug) $display("Wrote something for addr", fshow(cacheReq.addr));
      hitQ.enq(reqType == Ld ? finalRespData : 0);
    end
    cacheState <= Ready;
  endrule

  rule downgrade_start_rule if (cacheState != FinalResp &&
                                downgradeState == DowngradeStart &&
                                fromMem.hasReq && !fromMem.hasResp);

    CacheMemReq req = fromMem.first().Req;
    fromMem.deq();
    
    LineIndex li = req.addr[valueOf(NumCacheLineBits) - 1 : 0];
    MSI currentState = cacheMSIs[li];

    if (debug) begin
      $display("Downgrade start rule from MSI ", fshow(currentState));
    end
    
    if (currentState > req.state) begin
      if (currentState == M) begin
        dataArray.portB.request.put(BRAMRequest{write: False, // False for read
                                              responseOnWrite: False,
                                              address: li,
                                              datain: ?});
        downgradeState <= DowngradeFinish;
      end else begin
        cacheMSIs[li] <= req.state;
        toMem.enq_resp(CacheMemResp{ child: id, addr: req.addr, state: req.state, data: Invalid});
      end
    end

    downgradeReq <= req;
  endrule

  rule downgrade_end_rule if (cacheState != FinalResp &&
                              downgradeState == DowngradeFinish);

    Line data <- dataArray.portB.response.get();
    LineIndex li = downgradeReq.addr[valueOf(NumCacheLineBits) - 1 : 0];
    cacheMSIs[li] <= downgradeReq.state;

    CacheMemResp resp = CacheMemResp{ child: id, addr: downgradeReq.addr, state: downgradeReq.state, data: tagged Valid(data) };
    toMem.enq_resp(resp);

    if (debug) begin
      $display("Downgrade end: returning data", fshow(resp));
    end
    
    downgradeState <= DowngradeStart;
  endrule

  method Action req(MemReq r) if (cacheState == Ready);

      AddrInfo ai = extractAddrInfo(r.addr);
      
      tagArray.portA.request.put(BRAMRequest{write: False, // False for read
                                            responseOnWrite: False,
                                            address: ai.lineIndex,
                                            datain: ?});
      
      dataArray.portA.request.put(BRAMRequest{write: False, // False for read
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

endmodule
