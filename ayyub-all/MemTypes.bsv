import Vector::*;


typedef 32 WordSize;
typedef 32 AddrSize;
typedef 128 NumCacheLines;
typedef 16 NumWordsPerLine;



typedef Bit#(WordSize) Word;

typedef TLog#(NumWordsPerLine) NumBlockBits;
typedef TLog#(NumCacheLines) NumCacheLineBits;

typedef TSub#(TSub#(TSub#(AddrSize, NumCacheLineBits), NumBlockBits), 2) NumTagBits;

typedef Bit#(NumBlockBits) BlockOffset;
typedef Bit#(NumCacheLineBits) LineIndex;
typedef Bit#(NumTagBits) CacheTag;

typedef Vector#(NumWordsPerLine, Word) Line;

typedef TMul#(WordSize, NumWordsPerLine) NumPackedLineBits;
typedef Bit#(NumPackedLineBits) PackedLine;

typedef Bit#(AddrSize) CacheAddr;

typedef TAdd#(NumTagBits, NumCacheLineBits) NumLineAddrBits;
typedef Bit#(NumLineAddrBits) LineAddr;



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
