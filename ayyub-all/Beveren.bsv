import ClientServer::*;
import GetPut::*;
import Randomizable::*;
import MainMem::*;
import MemTypes::*;
import Cache::*;


module mkBeveren(Empty);
    let verbose = False;
    Randomize#(CacheReq) randomMem <- mkGenericRandomizer;
    
    MainMemRef mainRef <- mkMainMemFast(); //Initialize both to 0
    MainMem mainMem <- mkMainMem(); //Initialize both to 0
    Cache cache <- mkCache;
    
    Reg#(Bit#(32)) deadlockChecker <- mkReg(0); 
    Reg#(Bit#(32)) counterIn <- mkReg(0); 
    Reg#(Bit#(32)) counterOut <- mkReg(0); 
    Reg#(Bool) doinit <- mkReg(True);

    rule connectCacheDram;
        let lineReq <- cache.getToMem();
        mainMem.put(lineReq);
    endrule
    rule connectDramCache;
        let resp <- mainMem.get;
        cache.putFromMem(resp);
    endrule

    rule start (doinit);
        randomMem.cntrl.init;
        doinit <= False;
    endrule 

    rule reqs (counterIn <= 50000);
       let newrand <- randomMem.next;
       deadlockChecker <= 0;
       CacheReq newreq = newrand;
       newreq.addr = {0,newreq.addr[13:2],2'b0};
       if ( newreq.write == 0) counterIn <= counterIn + 1;

       mainRef.put(newreq);
       cache.putFromProc(newreq);
    endrule

    rule resps;
       counterOut <= counterOut + 1; 
       if (verbose) $display("Got response\n");
       let resp1 <- cache.getToProc() ;
       let resp2 <- mainRef.get();
       if (resp1 != resp2) begin
           $display("The cache answered %x instead of %x\n", resp1, resp2);
           $display("FAILED\n");
           $finish;
       end 
       if (counterOut == 49999) begin
           $display("PASSED\n");
           $finish;
       end
    endrule

    rule deadlockerC;
       deadlockChecker <= deadlockChecker + 1;
       if (deadlockChecker > 1000) begin
           $display("The cache deadlocks\n");
           $finish;
       end
    endrule
endmodule
