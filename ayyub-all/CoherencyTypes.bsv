import Vector::*;
import MemTypes::*;

typedef enum { M, S, I } MSI deriving( Bits, Eq, FShow );

typedef enum {
	Request, Response
} ReqRes deriving (Eq, FShow, Bits);

typedef Bit#(1) WhichCache;

typedef struct {
                Vector#(16, Word) data;
                LineAddr addr;
                MSI msi;
                ReqRes reqres;
                WhichCache whichcache;
} CoherencyMessage deriving (Eq, FShow, Bits);

typedef 2 CoreNum;
typedef Bit#(TLog#(CoreNum)) CoreID;
typedef Bit#(TLog#(TAdd#(1, CoreNum))) CoreIDPlusOne;


typedef struct{
    CoreID            child;
    LineAddr              addr;
    MSI               state;
    Maybe#(Line) data;
} CacheMemResp deriving(Eq, Bits, FShow);
typedef struct{
    CoreID      child;
    LineAddr        addr;
    MSI         state;
} CacheMemReq deriving(Eq, Bits, FShow);
typedef union tagged {
    CacheMemReq     Req;
    CacheMemResp    Resp;
} CacheMemMessage deriving(Eq, Bits, FShow);



instance Ord#(MSI);
    function Bool \< ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == LT);
    endfunction
    function Bool \<= ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == LT) || (c == EQ);
    endfunction
    function Bool \> ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == GT);
    endfunction
    function Bool \>= ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == GT) || (c == EQ);
    endfunction

    // This should implement M > S > I
    function Ordering compare( MSI x, MSI y );
        if( x == y ) begin
            // MM SS II
            return EQ;
        end else if( x == M || y == I) begin
            // MS MI SI
            return GT;
        end else begin
            // SM IM IS
            return LT;
        end
    endfunction

    function MSI min( MSI x, MSI y );
        if( x < y ) begin
            return x;
        end else begin
            return y;
        end
    endfunction
    function MSI max( MSI x, MSI y );
        if( x > y ) begin
            return x;
        end else begin
            return y;
        end
    endfunction
endinstance
// Wide memory interface
// This is defined here since it depends on the CacheLine type
typedef struct{
    Bit#(NumPackedLineBits) write_en;  // Word write enable
    LineAddr                 addr;
    Line            data;      // Vector#(CacheLineWords, Data)
} WideMemReq deriving(Eq,Bits,FShow);

typedef Line WideMemResp;
interface WideMem;
    method Action req(WideMemReq r);
    method ActionValue#(Line) resp;
	method Bool respValid;
endinterface
