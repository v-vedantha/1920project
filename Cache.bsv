import BRAM::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import MemTypes::*;

interface Cache;
    method Action putFromProc(MainMemReq e);
    method ActionValue#(MainMemResp) getToProc();
    method ActionValue#(MainMemReq) getToMem();
    method Action putFromMem(MainMemResp e);
endinterface

module mkCache(Cache);
  // TODO Write a Cache
  BRAM_Configure cfg = defaultValue;
  BRAM1Port#(CacheLineAddr, Line) cache <- mkBRAM1Server(cfg);

  Vector#(128, Reg#(State)) stateVector <- replicateM(mkReg(unpack(0)));
  Vector#(128, Reg#(Bool)) dirtyVector <- replicateM(mkReg(unpack(0)));

  FIFO#(MainMemReq) memReqQ <- mkFIFO;
  FIFO#(MainMemResp) memRespQ <- mkFIFO;

  FIFO#(Bit#(128)) hitQ <- mkFIFO;
  FIFO#(Store_buffer_entry) store_buffer <- mkSizedFIFO(1);
  FIFO#(Store_buffer_entry) readBuffer <- mkSizedFIFO(1);
  FIFO#(Bit#(512)) out_buffer <- mkFIFO;

  Reg#(MainMemReq) missReq <- mkReg(unpack(0));

  Reg#(Mshr_state) mshr <- mkReg(READY);
  Reg#(Store_buf_state) store_buf_state <- mkReg(READY);
  Reg#(Store_buf_state) read_buf_state <- mkReg(READY);
  Reg#(Bool) outstanding <- mkReg(False);
  Reg#(Bool) lock <- mkReg(False);


  rule processStoreBuf if(read_buf_state == READY);
    $display("Exectuing store ");
    let entry = store_buffer.first();
    // Check if the address hits in the cache
    Tag tag = entry.addr[25:7];
    CacheLineAddr addr = entry.addr[6:0];
    let state = stateVector[addr];
    let currtag = state.tag;
    let valid = state.valid;
    // let dirt = dirtyVector[cacheLineAddr];
    let hit = (currtag == tag);
    // If you get 
    if (valid) begin
      if (hit) begin
        // If it does, then write to the cache
        if (store_buf_state == READY && !lock) begin
          $display("Exectuing store1");
          cache.portA.request.put(BRAMRequest{write: True, responseOnWrite: False, address: addr, datain: entry.data});
          stateVector[addr] <= State{valid: True, tag: tag};
          // Then remove the entry from the store buffer
          store_buffer.deq();
        end
      end
      else begin
        // If not get the cached data
        if (store_buf_state == READY && !lock) begin
          $display("Exectuing store2");
          cache.portA.request.put(BRAMRequest{write: False, responseOnWrite: False, address: addr, datain: ?});

          store_buf_state <= STATE1;
          lock <= True;
        end

        if (store_buf_state == STATE1) begin
          $display("Exectuing store3");
          // On the next cycle write the cache data to mem
          let cacheData <- cache.portA.response.get();
          MainMemReq req = MainMemReq{write: unpack(1), addr: {currtag, addr}, data: cacheData};
          memReqQ.enq(req);
          store_buf_state <= STATE2;
        end

        // On the next push the new cache data into the cache
        if (store_buf_state == STATE2) begin
          $display("Exectuing store4");
          cache.portA.request.put(BRAMRequest{write: True, responseOnWrite: False, address: addr, datain: entry.data});
          stateVector[addr] <= State{valid: True, tag: tag};
          store_buffer.deq();
          store_buf_state <= READY;
          lock <= False;
        end
      end
    end
    else begin
      // If it doesn't valid then write to the cache
      if (store_buf_state == READY && !lock) begin
        $display("Exectuing store5");
        cache.portA.request.put(BRAMRequest{write: True, responseOnWrite: False, address: addr, datain: entry.data});
        stateVector[addr] <= State{valid: True, tag: tag};
        // Then remove the entry from the store buffer
        store_buffer.deq();
      end
    end

  endrule

  rule cacheQ if (store_buf_state == READY);
    $display("Exectuing cache");
    Store_buffer_entry entry = readBuffer.first();
    let addr = entry.addr;
    Tag tag = entry.addr[25:7];
    CacheLineAddr ccacheLineAddr = entry.addr[6:0];
    let state = stateVector[ccacheLineAddr];
    let currtag = state.tag;
    let valid = state.valid;
    let hit = (currtag == tag);
    if (valid && hit) begin
      if (read_buf_state == READY && !lock) begin
        $display("Exectuing cacheQ");
        cache.portA.request.put(BRAMRequest{write: False, responseOnWrite: False, address: ccacheLineAddr, datain: unpack(0)});
        read_buf_state <= STATE1;
        lock <= True;
      end

      if (read_buf_state == STATE1) begin
        $display("Exectuing cacheR");
        let cacheData <- cache.portA.response.get();
        out_buffer.enq(cacheData);
        readBuffer.deq();
        read_buf_state <= READY;
        lock <= False;
      end
    end
    else begin
      if (read_buf_state == READY && !lock) begin
        MainMemReq req = MainMemReq{write: unpack(0), addr: addr, data: ?};
        $display("Exectuing cacheS");
        memReqQ.enq(req);
        read_buf_state <= STATE1;
        lock <= True;
      end

      if (read_buf_state == STATE1) begin
        // If you get a response save it to output
        $display("Exectuing cacheT");
        let resp = memRespQ.first();
        memRespQ.deq();
        read_buf_state <= READY;
        out_buffer.enq(resp);
        // Add it to the store buffer
        store_buffer.enq(Store_buffer_entry{addr: addr, data: resp});
        readBuffer.deq();
        lock <= False;
      end
      
    end

     
  endrule


  method Action putFromProc(MainMemReq e) if (mshr == READY && !lock && !outstanding);
    $display("Exectuing putFromProc");
    // Check if the address is in the cache
    Tag tag = e.addr[25:7];
    CacheLineAddr addr = e.addr[6:0]; 

    let state = stateVector[addr];
    let currtag = state.tag;
    let hit = (currtag == tag);
    let valid = state.valid;
    let dirty = dirtyVector[addr];

    // If it is a write, then put it in the store buffer
    if (e.write == 1) begin
      $display("Exectuing putFromProc1");
      $display("Writing %x to %d", e.data, e.addr);
      store_buffer.enq(Store_buffer_entry{addr: e.addr, data: e.data});
    end
    else begin
      $display("Exectuing putFromProc2");
      outstanding <= True;
      $display("Reading from", e.addr);
      // If it is a read and in the store buffer, then return the store buffer data
      // if store_buffer.first()
      // Small issues here discuss
      readBuffer.enq(Store_buffer_entry{addr: e.addr, data: e.data});

    end

    // If it is, then send a put request
  endmethod

  method ActionValue#(MainMemResp) getToProc();
    $display("Exectuing getToProc");
    // Return the cache element if a response is valid
    let out = out_buffer.first();
    outstanding <= False;
    out_buffer.deq();
    return out;
  endmethod

  method ActionValue#(MainMemReq) getToMem();
    // This seems like a waste, but maybe it's used for the memory thing
    let out = memReqQ.first();
    memReqQ.deq();
    return out;
  endmethod

  method Action putFromMem(MainMemResp e);
    // Same as above
    memRespQ.enq(e);
  endmethod


endmodule
