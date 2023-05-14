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




typedef Word MemResp;

// just for debugging, add ID to each req
//`ifdef DEBUG
typedef Bit#(32) MemReqID;
//`else
//typedef Bit#(0) MemReqID;
//`endif

typedef enum{Ld, St, Lr, Sc, Fence} MemOp deriving(Eq, Bits, FShow);

typedef struct{
    MemOp op;
    CacheAddr  addr;
    Word  data;
	MemReqID rid; // unique for debug mode
} MemReq deriving(Eq, Bits, FShow);


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
