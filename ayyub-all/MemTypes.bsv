import Vector::*;

typedef Bit#(32) LineAddr;
typedef struct { 
                Bit#(1) write;
                LineAddr addr;
                Bit#(512) data;
               } MainMemReq deriving (Eq, FShow, Bits, Bounded);

typedef Bit#(512) MainMemResp;

typedef Bit#(32) Word;

typedef Vector#(16, Word) CacheLine;