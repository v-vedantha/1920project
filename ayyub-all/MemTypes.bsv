typedef Bit#(32) LineAddr;
typedef struct { 
                Bit#(1) write;
                LineAddr addr;
                Bit#(32) data;
               } MainMemReq deriving (Eq, FShow, Bits, Bounded);

typedef Bit#(32) MainMemResp;

typedef Bit#(512) CWord;

typedef Bit#(32) Word;
