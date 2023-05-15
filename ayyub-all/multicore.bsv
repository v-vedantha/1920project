import RVUtil::*;
import Vector::*;
import BRAM::*;
import CoherencyTypes::*;
import MessageFifo::*;
import MessageRouter::*;
import pipelined::*;
import FIFO::*;
import MemTypes::*;
import SingleCore::*;
import WideMem::*;
import PPP::*;
import DCache::*;

function Bit#(1) toWrite(Bit#(4) byte_en);
    return byte_en == 0 ? 0 : 1;
endfunction

function Bit#(64) toByteEn(Bit#(1) write);
    return (write == 1) ? signExtend(1'b1) : 0;
endfunction

module mkmulticore(Empty);
    // Instantiate the dual ported memory
    // BRAM2PortBE#(Bit#(30), Word, 4) bram <- mkBRAM2ServerBE(cfg);

    Reg#(Bit#(32)) cycle_count <- mkReg(0);

    // Cache iCache <- mkDCache();
    // Cache dCache <- mkDCache();

    // Message routers
    Vector#(CoreNum, MessageFifo#(2)) c2r <- replicateM(mkMessageFifo);
    // router to cache
    Vector#(CoreNum, MessageFifo#(2)) r2c <- replicateM(mkMessageFifo);
    // router to memory
    MessageFifo#(2) r2m <- mkMessageFifo;
    // memory to router
    MessageFifo#(2) m2r <- mkMessageFifo;

    let router <- mkMessageRouter(
		map(toMessageGet, c2r), 
		map(toMessagePut, r2c), 
		toMessageGet(m2r), 
		toMessagePut(r2m) 
	);

	RefMem refMem <- mkRefDummyMem;
    // Connect Cache to router
    DCache iCache1 <- mkDCache(0, toMessageGet(r2c[0]), toMessagePut(c2r[0]), refMem.dMem[0]);
    // DCache iCache2 <- mkDCache(2, toMessageGet(r2c[2]), toMessagePut(c2r[2]), refMem.dMem[0]);
    DCache dCache1 <- mkDCache(1, toMessageGet(r2c[1]), toMessagePut(c2r[1]), refMem.dMem[0]);
    // DCache dCache2 <- mkDCache(3, toMessageGet(r2c[3]), toMessagePut(c2r[3]), refMem.dMem[0]);
    // Memory 
    WideMem widemem <- mkWideMem;

    // PPP
    Empty ppp <- mkPPP(toMessageGet(r2m), toMessagePut(m2r), widemem);

    // Connect Cache to Processor
    RVIfc rv_core1 <- mkpipelined(0);
    // RVIfc rv_core2 <- mkpipelined;

    Empty core1 <- mkSingleCore(iCache1, dCache1, rv_core1);
    // Empty core2 <- mkSingleCore(iCache2, dCache2, rv_core2);



    rule tic;
	    cycle_count <= cycle_count + 1;
    endrule
endmodule
