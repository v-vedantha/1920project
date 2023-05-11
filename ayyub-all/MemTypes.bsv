import Vector::*;

typedef Bit#(32) Word;
typedef Vector#(16, Word) Line;

typedef Bit#(32) CacheAddr;
typedef Bit#(26) LineAddr; // 32 - 4 (block) - 2 (multiple of 4)

typedef struct { 
                Bit#(1) write;
                CacheAddr addr;
                Word data;
               } CacheReq deriving (Eq, FShow, Bits, Bounded);
typedef struct { 
                Bit#(1) write;
                LineAddr addr;
                Line data;
               } MainMemReq deriving (Eq, FShow, Bits, Bounded);

typedef Line MainMemResp;